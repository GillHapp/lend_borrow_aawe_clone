// pragma solidity ^0.8.26;

// import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
// import "@openzeppelin/contracts/access/Ownable.sol";


// import {aToken} from "./aToken.sol";

// contract Lending is Ownable {
//     uint256 public rewardRate = 1;
//     aToken public atoken;
//     AggregatorV3Interface internal priceFeed;

//     struct UserBalance {
//         uint256 ethDeposited;
//         uint256 aTokenMinted;
//         uint256 depositTimestamp;
//         uint256 unclaimedRewards;
//     }

//     mapping(address => UserBalance) public balances;

//     constructor(address _atoken,address _priceFeed) Ownable(msg.sender) {
//         atoken = aToken(_atoken);
//          priceFeed = AggregatorV3Interface(_priceFeed);
//     }

//     function depositETH() external payable {
//         require(msg.value > 0, "Send some ETH");
//         uint256 gweiAmount = msg.value / 1 gwei;
//         require(gweiAmount > 0, "Send at least 1 gwei");

//         UserBalance storage user = balances[msg.sender];

//         if (user.ethDeposited > 0) {
//             uint256 pendingReward = calculateReward(msg.sender);
//             user.unclaimedRewards += pendingReward;
//         }

//         user.ethDeposited += msg.value;
//         user.aTokenMinted += gweiAmount;
//         user.depositTimestamp = block.timestamp;

//         atoken.mint(msg.sender, gweiAmount * 1e18);
//     }

//  function calculateReward(address userAddr) public view returns (uint256) {
//     UserBalance memory user = balances[userAddr];
//     require(user.ethDeposited > 0, "No deposit");

//     uint256 timeElapsed = block.timestamp - user.depositTimestamp;

//     // Require full 30-hour interval to apply reward
//     if (timeElapsed < 30 hours) {
//         return user.unclaimedRewards; // no new reward yet
//     }

//     uint256 intervals = timeElapsed / (30 hours);
//     uint256 ethInGwei = user.ethDeposited / 1 gwei;
//     uint256 currentScale = getLatestEthUsdPrice();

//     uint256 reward = (ethInGwei * intervals * rewardRate) / currentScale;

//     return reward + user.unclaimedRewards;
// }


//     function getContractEthBalance() external view returns (uint256) {
//         return address(this).balance;
//     }

//     function withdrawAllETH() external onlyOwner {
//         payable(msg.sender).transfer(address(this).balance);
//     }

//     function getAPR() public view returns (uint256) {
//         uint256 intervalsPerYear = (365 * 24) / 30;
//         uint256 currentScale = getLatestEthUsdPrice();

//         uint256 apr = (rewardRate * intervalsPerYear * 10000) / currentScale;
//         return apr;
//     }

//     function getAPY() public view returns (uint256) {
//         uint256 apr = getAPR();

//         uint256 daysInYear = 365;
//         uint256 base = 1e6;
//         uint256 ratePerDay = (apr * base) / (daysInYear * 10000);

//         uint256 apy = base;
//         for (uint256 i = 0; i < daysInYear; i++) {
//             apy = (apy * (base + ratePerDay)) / base;
//         }

//         return (apy - base) * 10000 / base;
//     }

//    function redeemaToken() external {
//     UserBalance storage user = balances[msg.sender];
//     require(user.ethDeposited > 0, "No deposit");

//     uint256 pendingReward = calculateReward(msg.sender);
//     user.unclaimedRewards += pendingReward;

//     uint256 totalGwei = user.aTokenMinted + user.unclaimedRewards;
//     uint256 totalETHToReturn = (totalGwei * 1 gwei);

//     require(address(this).balance >= totalETHToReturn, "Insufficient contract balance");

//     // Burn aTokens
// atoken.burn(msg.sender, user.aTokenMinted * 1e18);

//     // Send ETH back
//     payable(msg.sender).transfer(totalETHToReturn);

//     // Reset user balance
//     delete balances[msg.sender];

//     // emit Redeemed(msg.sender, totalETHToReturn, totalGwei);
// }

//  function getLatestEthUsdPrice() public view returns (uint256) {
//     (, int256 price,,,) = priceFeed.latestRoundData();
//     return uint256(price)/10**8; // 8 decimals
// }


// 0x5C2686Ed7d34cA688Ea267dA56C963Df6cF05288
// 0x5C2686Ed7d34cA688Ea267dA56C963Df6cF05288

// 0x3b41Fd71fe140E7b32A79F504ef70e7712b1935F


// 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59
// 0x779877A7B0D9E8603169DdbD7836e478b4624789
// 0x694AA1769357215DE4FAC081bf1f309aDC325306
// 0xc59E3633BAAC79493d908e63626716e204A45EdF
// 14767482510784806043




// 0xe890e036b73Cf6D3101A8c63be4A496136A3fBDE


// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {OwnerIsCreator} from "@chainlink/contracts/src/v0.8/shared/access/OwnerIsCreator.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {IERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/contracts/applications/CCIPReceiver.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract TokenTransferor is OwnerIsCreator,CCIPReceiver {
    using SafeERC20 for IERC20;
     AggregatorV3Interface internal dataFeedETHToUSD;// this is for eth usd
     AggregatorV3Interface internal dataFeedLinkToUSD;// this is for Link usd
    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees); // Used to make sure contract has enough balance to cover the fees.
    error NothingToWithdraw(); // Used when trying to withdraw Ether but there's nothing to withdraw.
    error FailedToWithdrawEth(address owner, address target, uint256 value); // Used when the withdrawal of Ether fails.
    error DestinationChainNotAllowlisted(uint64 destinationChainSelector); // Used when the destination chain has not been allowlisted by the contract owner.
    error InvalidReceiverAddress(); // Used when the receiver address is 0.
    // Event emitted when the tokens are transferred to an account on another chain.
 // Custom errors to provide more descriptive revert messages.
    error DestinationChainNotAllowed(uint64 destinationChainSelector); // Used when the destination chain has not been allowlisted by the contract owner.
    error SourceChainNotAllowed(uint64 sourceChainSelector); // Used when the source chain has not been allowlisted by the contract owner.
    error SenderNotAllowed(address sender); // Used when the sender has not been allowlisted by the contract owner.
    struct UserPosition {
    uint256 collateralETH;
    uint256 borrowedLINK; 
    uint256 timestamp;
}
    mapping(address => UserPosition) public userPositions;

    event TokensTransferred(
        bytes32 indexed messageId, // The unique ID of the message.
        uint64 indexed destinationChainSelector, // The chain selector of the destination chain.
        address receiver, // The address of the receiver on the destination chain.
        address token, // The token address that was transferred.
        uint256 tokenAmount, // The token amount that was transferred.
        address feeToken, // the token address used to pay CCIP fees.
        uint256 fees // The fees paid for sending the message.
    );

     event MessageReceived(
        bytes32 indexed messageId, // The unique ID of the CCIP message.
        uint64 indexed sourceChainSelector, // The chain selector of the source chain.
        address sender, // The address of the sender from the source chain.
        string text, // The text that was received.
        address token, // The token address that was transferred.
        uint256 tokenAmount // The token amount that was transferred.
    );

    bytes32 private s_lastReceivedMessageId; // Store the last received messageId.
    address private s_lastReceivedTokenAddress; // Store the last received token address.
    uint256 private s_lastReceivedTokenAmount; // Store the last received amount.
    string private s_lastReceivedText; // Store the last received text.


    event UserLiquidated(
    address indexed liquidator,
    address indexed user,
    uint256 ethCollateralSeized,
    uint256 linkRepaid
);

  modifier onlyAllowlistedDestinationChain(uint64 _destinationChainSelector) {
        if (!allowlistedDestinationChains[_destinationChainSelector])
            revert DestinationChainNotAllowed(_destinationChainSelector);
        _;
    }

    /// @dev Modifier that checks the receiver address is not 0.
    /// @param _receiver The receiver address.
    modifier validateReceiver(address _receiver) {
        if (_receiver == address(0)) revert InvalidReceiverAddress();
        _;
    }

    /// @dev Modifier that checks if the chain with the given sourceChainSelector is allowlisted and if the sender is allowlisted.
    /// @param _sourceChainSelector The selector of the destination chain.
    /// @param _sender The address of the sender.
    modifier onlyAllowlisted(uint64 _sourceChainSelector, address _sender) {
        if (!allowlistedSourceChains[_sourceChainSelector])
            revert SourceChainNotAllowed(_sourceChainSelector);
        if (!allowlistedSenders[_sender]) revert SenderNotAllowed(_sender);
        _;
    }


    // Mapping to keep track of allowlisted destination chains.
    mapping(uint64 => bool) public allowlistedChains;

      // Mapping to keep track of allowlisted destination chains.
    mapping(uint64 => bool) public allowlistedDestinationChains;

    // Mapping to keep track of allowlisted source chains.
    mapping(uint64 => bool) public allowlistedSourceChains;

    // Mapping to keep track of allowlisted senders.
    mapping(address => bool) public allowlistedSenders;

    IRouterClient private s_router;

    IERC20 private s_linkToken;

    constructor(address _router, address _link, AggregatorV3Interface _priceFeedETHToUSD, AggregatorV3Interface _priceFeedLinkToUSD) CCIPReceiver(_router) {
        s_router = IRouterClient(_router);
        s_linkToken = IERC20(_link);
         dataFeedETHToUSD = AggregatorV3Interface(
            _priceFeedETHToUSD
        );
         dataFeedLinkToUSD = AggregatorV3Interface(
            _priceFeedLinkToUSD
        );
    }

    modifier onlyAllowlistedChain(uint64 _destinationChainSelector) {
        if (!allowlistedChains[_destinationChainSelector])
            revert DestinationChainNotAllowlisted(_destinationChainSelector);
        _;
    }




    function allowlistDestinationChain(
        uint64 _destinationChainSelector,
        bool allowed
    ) external onlyOwner {
        allowlistedChains[_destinationChainSelector] = allowed;
    }

    function borrowLinkAndCollETHAndPayLINK(
    uint64 _destinationChainSelector,
     address _token
    
)
    external
    onlyAllowlistedChain(_destinationChainSelector)
    validateReceiver(msg.sender)

    payable 
    returns (bytes32 messageId)
{
    require(msg.value > 1 gwei, "Must send ETH as collateral");

    uint256 loanAmount = _calculateLoanAmount(msg.value);

    // Load user's current position
    UserPosition storage position = userPositions[msg.sender];

    // Update position data
    position.collateralETH += msg.value;
    position.borrowedLINK += loanAmount;

    // Only set timestamp if this is the first time they're borrowing
    if (position.timestamp == 0) {
        position.timestamp = block.timestamp;
    }

    // Build CCIP message
    Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
         msg.sender,
         _token,
        loanAmount,
        address(s_linkToken)
    );

    // Calculate CCIP fee
    uint256 fees = s_router.getFee(_destinationChainSelector, evm2AnyMessage);

    // Take LINK as fee from the user
    bool success = s_linkToken.transferFrom(msg.sender, address(this), fees);
    require(success, "LINK fee transfer failed");

    if (fees > s_linkToken.balanceOf(address(this))) {
        revert NotEnoughBalance(s_linkToken.balanceOf(address(this)), fees);
    }

    s_linkToken.approve(address(s_router), fees);
    // Approve router for fee and token transfer
    IERC20(_token).approve(address(s_router), loanAmount);

    // Send message via Chainlink CCIP
    messageId = s_router.ccipSend(_destinationChainSelector, evm2AnyMessage);

    emit TokensTransferred(
        messageId,
        _destinationChainSelector,
        msg.sender,
        address(s_linkToken),
        loanAmount,
        address(s_linkToken),
        fees
    );

    return messageId;
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
                data: "", // No data
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
     function getChainlinkDataFeedForLinkUSD() public view returns (int) {
        (
            /* uint80 roundId */,
            int256 answer,
            /*uint256 startedAt*/,
            /*uint256 updatedAt*/,
            /*uint80 answeredInRound*/
        ) = dataFeedLinkToUSD.latestRoundData();
        return (answer/10**8);
    }

    function getCollateralValueInUSD(uint256 ethAmount) public view returns (uint256) {
    require(ethAmount>0 ,"Invalid amount");
    int usdInEth = getChainlinkDataFeedForETHUSD();
    require(usdInEth > 0, "Invalid price feed");

    uint256 usdValue = (ethAmount * uint256(usdInEth)) / 1e18;
    return usdValue;
}

function _calculateLoanAmount(uint256 ethAmount) internal view returns (uint256) {
    uint256 usdInEth = getCollateralValueInUSD(ethAmount);
    int256 usdInLink = getChainlinkDataFeedForLinkUSD();
    require(usdInLink > 0, "Invalid LINK/USD price");

    uint256 loanAMount =  (usdInEth * 75 * 1e18) / (uint256(usdInLink) * 100);
    return loanAMount;
}
function liquidate(address user) external {
    UserPosition storage position = userPositions[user];

    require(position.collateralETH > 0, "No collateral found");
    require(position.borrowedLINK > 0, "No borrowed amount");

    // Step 1: Get ETH collateral value in USD
    uint256 collateralUSD = getCollateralValueInUSD(position.collateralETH);

    // Step 2: Get LINK price
    int linkPrice = getChainlinkDataFeedForLinkUSD();
    require(linkPrice > 0, "Invalid LINK/USD price");

    // Step 3: Calculate debt in USD
    uint256 borrowedLINK = position.borrowedLINK;
    uint256 debtUSD = (borrowedLINK * uint256(linkPrice)) / 1e18;

    // Step 4: Check if debt ≥ 80% of collateral
    require(debtUSD * 100 >= collateralUSD * 80, "User is not eligible for liquidation");

    // Step 5: Transfer LINK from liquidator to protocol
    s_linkToken.safeTransferFrom(msg.sender, address(this), borrowedLINK);

    // Step 6: Transfer collateral ETH to liquidator
    uint256 collateral = position.collateralETH;

    // Step 7: Delete the user's position
    delete userPositions[user];

    // Step 8: Send ETH to liquidator
    (bool sent, ) = msg.sender.call{value: collateral}("");
    require(sent, "Collateral transfer failed");

    // Emit liquidation event
    emit UserLiquidated(msg.sender, user, collateral, borrowedLINK);
}

function calculateInterestFee(address user) public view returns (
    uint256 monthsPassed,
    uint256 interestUSD,
    uint256 collateralUSD
) {
    UserPosition memory position = userPositions[user];
    require(position.collateralETH > 0, "No collateral");

    // 1. Calculate time passed
    uint256 secondsPassed = block.timestamp - position.timestamp;
    monthsPassed = secondsPassed / 30 days;
    if (monthsPassed == 0) monthsPassed = 1; // charge at least 1 month

    // 2. Get collateral value in USD
    collateralUSD = getCollateralValueInUSD(position.collateralETH);

    // 3. Calculate interest: 1% per month
    interestUSD = (collateralUSD * monthsPassed *2) / 100;

    return (monthsPassed, interestUSD, collateralUSD);
}

/// @notice Withdraws all ETH in the contract to the owner.
function withdrawAllETHToOwner() external onlyOwner {
    uint256 balance = address(this).balance;
    if (balance == 0) revert NothingToWithdraw();

    (bool success, ) = owner().call{value: balance}("");
    if (!success) revert FailedToWithdrawEth(msg.sender, owner(), balance);
}

/// @notice Withdraws all LINK tokens in the contract to the owner.
function withdrawAllLinkToOwner() external onlyOwner {
    uint256 linkBalance = s_linkToken.balanceOf(address(this));
    if (linkBalance == 0) revert NothingToWithdraw();

    s_linkToken.safeTransfer(owner(), linkBalance);
}

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
    // Decode the sender and data
    address user = abi.decode(any2EvmMessage.sender, (address));
    uint256 repaidAmount = any2EvmMessage.destTokenAmounts[0].amount;

    // Validate token (must be LINK)
    require(any2EvmMessage.destTokenAmounts[0].token == address(s_linkToken), "Invalid token");

    UserPosition storage position = userPositions[user];
    require(position.collateralETH > 0, "No collateral");
    require(position.borrowedLINK > 0, "No borrowed debt");
    require(repaidAmount >= position.borrowedLINK, "Repayment too small");

    // Get interest fee in USD
    (, uint256 interestUSD, ) = calculateInterestFee(user);
    
    // Convert interestUSD to ETH using Chainlink price feed
    int ethUsd = getChainlinkDataFeedForETHUSD();
    require(ethUsd > 0, "Invalid ETH/USD price");
    uint256 interestInETH = (interestUSD * 1e18) / uint256(ethUsd);

    // Cap interest to not exceed collateral
    if (interestInETH > position.collateralETH) {
        interestInETH = position.collateralETH;
    }

    uint256 refundETH = position.collateralETH - interestInETH;

    // Clear user position
    delete userPositions[user];

    // Refund ETH to user
    (bool sent, ) = user.call{value: refundETH}("");
    require(sent, "Refund failed");

    // Optionally: Keep interestInETH or send to owner
    // (bool feeSent, ) = owner().call{value: interestInETH}();
    // require(feeSent, "Fee transfer failed");

    // Store internal state
    s_lastReceivedMessageId = any2EvmMessage.messageId;
    s_lastReceivedTokenAddress = any2EvmMessage.destTokenAmounts[0].token;
    s_lastReceivedTokenAmount = any2EvmMessage.destTokenAmounts[0].amount;
    s_lastReceivedText = "Loan repaid and ETH refunded with fee";

    emit MessageReceived(
        any2EvmMessage.messageId,
        any2EvmMessage.sourceChainSelector,
        user,
        s_lastReceivedText,
        s_lastReceivedTokenAddress,
        s_lastReceivedTokenAmount
    );
}


}





