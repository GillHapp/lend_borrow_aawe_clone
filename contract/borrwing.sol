// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
// 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59
// 0x779877A7B0D9E8603169DdbD7836e478b4624789
// 0x694AA1769357215DE4FAC081bf1f309aDC325306
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {OwnerIsCreator} from "@chainlink/contracts/src/v0.8/shared/access/OwnerIsCreator.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/contracts/applications/CCIPReceiver.sol";
import {IERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @title - A simple messenger contract for transferring/receiving tokens and data across chains.
contract ProgrammableTokenTransfers is CCIPReceiver, OwnerIsCreator {
    using SafeERC20 for IERC20;
    AggregatorV3Interface internal dataFeedETHToUSD;
    // Custom errors to provide more descriptive revert messages.
    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees); // Used to make sure contract has enough balance to cover the fees.
    error NothingToWithdraw(); // Used when trying to withdraw Ether but there's nothing to withdraw.
    error FailedToWithdrawEth(address owner, address target, uint256 value); // Used when the withdrawal of Ether fails.
    error DestinationChainNotAllowed(uint64 destinationChainSelector); // Used when the destination chain has not been allowlisted by the contract owner.
    error SourceChainNotAllowed(uint64 sourceChainSelector); // Used when the source chain has not been allowlisted by the contract owner.
    error SenderNotAllowed(address sender); // Used when the sender has not been allowlisted by the contract owner.
    error InvalidReceiverAddress(); // Used when the receiver address is 0.

    // Event emitted when a message is sent to another chain.
    event MessageSent(
        bytes32 indexed messageId, // The unique ID of the CCIP message.
        uint64 indexed destinationChainSelector, // The chain selector of the destination chain.
        address receiver, // The address of the receiver on the destination chain.// The text being sent.
        address token, // The token address that was transferred.
        uint256 tokenAmount, // The token amount that was transferred.
        address feeToken, // the token address used to pay CCIP fees.
        uint256 fees // The fees paid for sending the message.
    );

    // Event emitted when a message is received from another chain.
    event MessageReceived(
        bytes32 indexed messageId, // The unique ID of the CCIP message.
        uint64 indexed sourceChainSelector, // The chain selector of the source chain.
        address sender, // The address of the sender from the source chain.
        string text, // The text that was received.
        address token, // The token address that was transferred.
        uint256 tokenAmount // The token amount that was transferred.
    );

    event LoanRepaid(
    address indexed user,
    uint256 repaidAmount,
    uint256 interestPaidInETH,
    uint256 returnedETH
    );

    bytes32 private s_lastReceivedMessageId; // Store the last received messageId.
    address private s_lastReceivedTokenAddress; // Store the last received token address.
    uint256 private s_lastReceivedTokenAmount; // Store the last received amount.
    string private s_lastReceivedText; // Store the last received text.

    struct CollateralInfo {
    uint256 ethAmount;       // ETH collateral
    uint256 loanAmount;      // Borrowed token amount
    uint256 loanStartTime;   // Timestamp when loan was issued
}


    mapping(address => CollateralInfo) public userCollateral;

    // Mapping to keep track of allowlisted destination chains.
    mapping(uint64 => bool) public allowlistedDestinationChains;

    // Mapping to keep track of allowlisted source chains.
    mapping(uint64 => bool) public allowlistedSourceChains;

    // Mapping to keep track of allowlisted senders.
    mapping(address => bool) public allowlistedSenders;

    IERC20 private s_linkToken;

    constructor(address _router, address _link, AggregatorV3Interface _priceFeedETHToUSD) CCIPReceiver(_router) {
        s_linkToken = IERC20(_link);
         dataFeedETHToUSD = AggregatorV3Interface(
            _priceFeedETHToUSD
        );
    }

    modifier onlyAllowlistedDestinationChain(uint64 _destinationChainSelector) {
        if (!allowlistedDestinationChains[_destinationChainSelector])
            revert DestinationChainNotAllowed(_destinationChainSelector);
        _;
    }

    modifier validateReceiver(address _receiver) {
        if (_receiver == address(0)) revert InvalidReceiverAddress();
        _;
    }

    modifier onlyAllowlisted(uint64 _sourceChainSelector, address _sender) {
        if (!allowlistedSourceChains[_sourceChainSelector])
            revert SourceChainNotAllowed(_sourceChainSelector);
        if (!allowlistedSenders[_sender]) revert SenderNotAllowed(_sender);
        _;
    }

    function allowlistDestinationChain(
        uint64 _destinationChainSelector,
        bool allowed
    ) external onlyOwner {
        allowlistedDestinationChains[_destinationChainSelector] = allowed;
    }

    function allowlistSourceChain(
        uint64 _sourceChainSelector,
        bool allowed
    ) external onlyOwner {
        allowlistedSourceChains[_sourceChainSelector] = allowed;
    }

    function allowlistSender(address _sender, bool allowed) external onlyOwner {
        allowlistedSenders[_sender] = allowed;
    }

    function sendMessagePayLINK(
        uint64 _destinationChainSelector,
        address _receiver,
        address _token,
        uint256 _amount
    )
        external
        onlyAllowlistedDestinationChain(_destinationChainSelector)
        validateReceiver(_receiver)
        returns (bytes32 messageId)
    {
        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        // address(linkToken) means fees are paid in LINK
        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
            _receiver,
            _token,
            _amount,
            address(s_linkToken)
        );

        // Initialize a router client instance to interact with cross-chain router
        IRouterClient router = IRouterClient(this.getRouter());

        // Get the fee required to send the CCIP message
        uint256 fees = router.getFee(_destinationChainSelector, evm2AnyMessage);

        if (fees > s_linkToken.balanceOf(address(this)))
            revert NotEnoughBalance(s_linkToken.balanceOf(address(this)), fees);

        // approve the Router to transfer LINK tokens on contract's behalf. It will spend the fees in LINK
        s_linkToken.approve(address(router), fees);

        // approve the Router to spend tokens on contract's behalf. It will spend the amount of the given token
        IERC20(_token).approve(address(router), _amount);

        // Send the message through the router and store the returned message ID
        messageId = router.ccipSend(_destinationChainSelector, evm2AnyMessage);

        // Emit an event with message details
        emit MessageSent(
            messageId,
            _destinationChainSelector,
            _receiver,
            _token,
            _amount,
            address(s_linkToken),
            fees
        );

        // Return the message ID
        return messageId;
    }

    function getLastReceivedMessageDetails()
        public
        view
        returns (
            bytes32 messageId,
            string memory text,
            address tokenAddress,
            uint256 tokenAmount
        )
    {
        return (
            s_lastReceivedMessageId,
            s_lastReceivedText,
            s_lastReceivedTokenAddress,
            s_lastReceivedTokenAmount
        );
    }

    /// handle a received message
   function _ccipReceive(
    Client.Any2EVMMessage memory any2EvmMessage
)
    internal
    override
    onlyAllowlisted(
        any2EvmMessage.sourceChainSelector,
        abi.decode(any2EvmMessage.sender, (address))
    )
{
    address user = abi.decode(any2EvmMessage.sender, (address));
    uint256 repaidAmount = any2EvmMessage.destTokenAmounts[0].amount;

    s_lastReceivedMessageId = any2EvmMessage.messageId;
    s_lastReceivedText = abi.decode(any2EvmMessage.data, (string));
    s_lastReceivedTokenAddress = any2EvmMessage.destTokenAmounts[0].token;
    s_lastReceivedTokenAmount = repaidAmount;

    emit MessageReceived(
        any2EvmMessage.messageId,
        any2EvmMessage.sourceChainSelector,
        user,
        abi.decode(any2EvmMessage.data, (string)),
        s_lastReceivedTokenAddress,
        repaidAmount
    );

    // Fetch user's loan info
    CollateralInfo storage info = userCollateral[user];
    require(info.loanAmount > 0, "No active loan");
    require(repaidAmount >= info.loanAmount, "Not enough repaid");

    // Calculate interest
    uint256 secondsElapsed = block.timestamp - info.loanStartTime;
    uint256 daysElapsed = secondsElapsed / 1 days;
    uint256 dailyRateBps = 200; // 2% per month = 200bps per 30 days
    uint256 interestBps = (dailyRateBps * daysElapsed) / 30;
    uint256 interest = (info.loanAmount * interestBps) / 10000;

    // Convert interest (USD) to ETH using price feed
    (, int256 ethPrice,,,) = dataFeedETHToUSD.latestRoundData();
    require(ethPrice > 0, "Invalid ETH price");
    uint256 interestInETH = (interest * 1e8) / uint256(ethPrice); // price feed is 8 decimals

    // Ensure user has enough ETH to cover interest
    require(info.ethAmount >= interestInETH, "Collateral < Interest");

    // Return remaining ETH to user
    uint256 remainingEth = info.ethAmount - interestInETH;
    if (remainingEth > 0) {
        (bool success, ) = user.call{value: remainingEth}("");
        require(success, "ETH transfer failed");
    }

    // Delete user's collateral record
    delete userCollateral[user];
}


    function _buildCCIPMessage(
        address _receiver,
        address _token,
        uint256 _amount,
        address _feeTokenAddress
    ) private pure returns (Client.EVM2AnyMessage memory) {
        // Set the token amounts
        Client.EVMTokenAmount[]
            memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: _token,
            amount: _amount
        });
        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        return
            Client.EVM2AnyMessage({
                receiver: abi.encode(_receiver), // ABI-encoded receiver address
                data: "", // ABI-encoded string
                tokenAmounts: tokenAmounts, // The amount and type of token being transferred
                extraArgs: Client._argsToBytes(
                    Client.GenericExtraArgsV2({
                        gasLimit: 0, // Gas limit for the callback on the destination chain
                        allowOutOfOrderExecution: true // Allows the message to be executed out of order relative to other messages from the same sender
                    })
                ),
                // Set the feeToken to a feeTokenAddress, indicating specific asset will be used for fees
                feeToken: _feeTokenAddress
            });
    }

    receive() external payable {}

    function withdraw(address _beneficiary) public onlyOwner {
        // Retrieve the balance of this contract
        uint256 amount = address(this).balance;

        // Revert if there is nothing to withdraw
        if (amount == 0) revert NothingToWithdraw();

        // Attempt to send the funds, capturing the success status and discarding any return data
        (bool sent, ) = _beneficiary.call{value: amount}("");

        // Revert if the send failed, with information about the attempted transfer
        if (!sent) revert FailedToWithdrawEth(msg.sender, _beneficiary, amount);
    }

    function withdrawLink() external onlyOwner {
    uint256 linkBalance = s_linkToken.balanceOf(address(this));
    if (linkBalance == 0) revert NothingToWithdraw();

    s_linkToken.safeTransfer(msg.sender, linkBalance);
    }

    function withdrawToken(
        address _beneficiary,
        address _token
    ) public onlyOwner {
        // Retrieve the balance of this contract
        uint256 amount = IERC20(_token).balanceOf(address(this));

        // Revert if there is nothing to withdraw
        if (amount == 0) revert NothingToWithdraw();

        IERC20(_token).safeTransfer(_beneficiary, amount);
    }

       function getChainlinkDataFeedForETHUSD() public view returns (int) {
        (
            /* uint80 roundId */,
            int256 answer,
            /*uint256 startedAt*/,
            /*uint256 updatedAt*/,
            /*uint80 answeredInRound*/
        ) = dataFeedETHToUSD.latestRoundData();
        return (answer/10**8);
    }

    function _calculateLoanTokenAmountFromETH(uint256 ethAmount) public view returns (uint256) {
    (
        , int256 ethUsdPrice, , , 
    ) = dataFeedETHToUSD.latestRoundData();
    require(ethUsdPrice > 0, "Invalid ETH price");
    
    // Assume ETH price feed has 8 decimals, so we scale to 18 decimals
    uint256 ethUsdValue = (ethAmount * uint256(ethUsdPrice)) / 1e8;

    // Return 70% of the value as loan in pegged USD token (1 token = $1)
    return (ethUsdValue * 70) / 100;
}
function sendMessageWithCollateralInETH(
    uint64 _destinationChainSelector,
    address _token // the pegged $1 token
)
    external
    payable
    onlyAllowlistedDestinationChain(_destinationChainSelector)
    validateReceiver(msg.sender)
    returns (bytes32 messageId)
{
    require(msg.value > 0, "Must send ETH as collateral");

    // Calculate amount of pegged tokens to transfer based on 70% LTV
    uint256 loanTokenAmount = _calculateLoanTokenAmountFromETH(msg.value);

    // Build CCIP message to send tokens cross-chain
    Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
        msg.sender,
        _token,
        loanTokenAmount,
        address(s_linkToken)
    );

    IRouterClient router = IRouterClient(this.getRouter());

    uint256 fees = router.getFee(_destinationChainSelector, evm2AnyMessage);
    if (fees > s_linkToken.balanceOf(address(this))) {
        revert NotEnoughBalance(s_linkToken.balanceOf(address(this)), fees);
    }

    // Approve LINK and token
    s_linkToken.approve(address(router), fees);
    IERC20(_token).approve(address(router), loanTokenAmount);

    // Send the message
    messageId = router.ccipSend(_destinationChainSelector, evm2AnyMessage);

    emit MessageSent(
        messageId,
        _destinationChainSelector,
        msg.sender,
        _token,
        loanTokenAmount,
        address(s_linkToken),
        fees
    );

   userCollateral[msg.sender] = CollateralInfo({
    ethAmount: msg.value,
    loanAmount: loanTokenAmount,
    loanStartTime: block.timestamp
});


    return messageId;
}


    function checkCollateralHealth(address user) external view returns (
    uint256 currentEthPrice,
    uint256 currentCollateralUsdValue,
    uint256 loanValue,
    uint256 ltvBasisPoints,
    string memory healthStatus
     ) {
    CollateralInfo memory info = userCollateral[user];
    require(info.ethAmount > 0, "No collateral found for user");

    (, int256 price,,,) = dataFeedETHToUSD.latestRoundData();
    require(price > 0, "Invalid ETH price");
    
    currentEthPrice = uint256(price); // in 8 decimals
    currentCollateralUsdValue = (info.ethAmount * currentEthPrice) / 1e8; // scaled to USD

    loanValue = info.loanAmount; // $1 per token
    ltvBasisPoints = (loanValue * 1e4) / currentCollateralUsdValue; // 100% = 10000 bps

    if (ltvBasisPoints >= 8000) {
        healthStatus = " HIGH RISK: LTV >= 80%";
    } else if (ltvBasisPoints >= 7000) {
        healthStatus = " Medium Risk: LTV >= 70%";
    } else {
        healthStatus = "Healthy";
    }

    return (
        currentEthPrice / 1e8, // $ value of 1 ETH
        currentCollateralUsdValue,
        loanValue,
        ltvBasisPoints,
        healthStatus
    );
}

function getUserLoanInfo(address user) external view returns (
    uint256 ethCollateral,
    uint256 loanAmount,
    uint256 loanStartTime
) {
    CollateralInfo memory info = userCollateral[user];
    return (info.ethAmount, info.loanAmount, info.loanStartTime);
}

function calculateInterestOwed(address user) external view returns (
    uint256 principal,
    uint256 interest,
    uint256 totalRepayable,
    uint256 daysElapsed
) {
    CollateralInfo memory info = userCollateral[user];
    require(info.loanAmount > 0, "No active loan");

    principal = info.loanAmount;
    uint256 secondsElapsed = block.timestamp - info.loanStartTime;
    daysElapsed = secondsElapsed / 1 days;

    // 2% monthly → 0.000666666... daily interest rate
    uint256 dailyRateBps = 200; // 2% monthly = 200 bps per 30 days ≈ 6.66 bps/day
    uint256 interestBps = (dailyRateBps * daysElapsed) / 30;

    // interest = principal * interestBps / 10,000
    interest = (principal * interestBps) / 10000;
    totalRepayable = principal + interest;

    return (principal, interest, totalRepayable, daysElapsed);
}



}
