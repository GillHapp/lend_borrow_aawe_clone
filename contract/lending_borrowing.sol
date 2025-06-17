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


// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {OwnerIsCreator} from "@chainlink/contracts/src/v0.8/shared/access/OwnerIsCreator.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {IERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";

contract TokenTransferor is OwnerIsCreator {
    using SafeERC20 for IERC20;

    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees); // Used to make sure contract has enough balance to cover the fees.
    error NothingToWithdraw(); // Used when trying to withdraw Ether but there's nothing to withdraw.
    error FailedToWithdrawEth(address owner, address target, uint256 value); // Used when the withdrawal of Ether fails.
    error DestinationChainNotAllowlisted(uint64 destinationChainSelector); // Used when the destination chain has not been allowlisted by the contract owner.
    error InvalidReceiverAddress(); // Used when the receiver address is 0.
    // Event emitted when the tokens are transferred to an account on another chain.
    event TokensTransferred(
        bytes32 indexed messageId, // The unique ID of the message.
        uint64 indexed destinationChainSelector, // The chain selector of the destination chain.
        address receiver, // The address of the receiver on the destination chain.
        address token, // The token address that was transferred.
        uint256 tokenAmount, // The token amount that was transferred.
        address feeToken, // the token address used to pay CCIP fees.
        uint256 fees // The fees paid for sending the message.
    );

    // Mapping to keep track of allowlisted destination chains.
    mapping(uint64 => bool) public allowlistedChains;

    IRouterClient private s_router;

    IERC20 private s_linkToken;

    constructor(address _router, address _link) {
        s_router = IRouterClient(_router);
        s_linkToken = IERC20(_link);
    }

    modifier onlyAllowlistedChain(uint64 _destinationChainSelector) {
        if (!allowlistedChains[_destinationChainSelector])
            revert DestinationChainNotAllowlisted(_destinationChainSelector);
        _;
    }

    modifier validateReceiver(address _receiver) {
        if (_receiver == address(0)) revert InvalidReceiverAddress();
        _;
    }

    function allowlistDestinationChain(
        uint64 _destinationChainSelector,
        bool allowed
    ) external onlyOwner {
        allowlistedChains[_destinationChainSelector] = allowed;
    }

    function transferTokensPayLINK(
        uint64 _destinationChainSelector,
        address _receiver,
        address _token,
        uint256 _amount
    )
        external
        onlyOwner
        onlyAllowlistedChain(_destinationChainSelector)
        validateReceiver(_receiver)
        returns (bytes32 messageId)
    {

        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
            _receiver,
            _token,
            _amount,
            address(s_linkToken)
        );

        // Get the fee required to send the message
        uint256 fees = s_router.getFee(
            _destinationChainSelector,
            evm2AnyMessage
        );

        if (fees > s_linkToken.balanceOf(address(this)))
            revert NotEnoughBalance(s_linkToken.balanceOf(address(this)), fees);

        // approve the Router to transfer LINK tokens on contract's behalf. It will spend the fees in LINK
        s_linkToken.approve(address(s_router), fees);

        // approve the Router to spend tokens on contract's behalf. It will spend the amount of the given token
        IERC20(_token).approve(address(s_router), _amount);

        // Send the message through the router and store the returned message ID
        messageId = s_router.ccipSend(
            _destinationChainSelector,
            evm2AnyMessage
        );

        // Emit an event with message details
        emit TokensTransferred(
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

    function transferTokensPayNative(
        uint64 _destinationChainSelector,
        address _receiver,
        address _token,
        uint256 _amount
    )
        external
        onlyOwner
        onlyAllowlistedChain(_destinationChainSelector)
        validateReceiver(_receiver)
        returns (bytes32 messageId)
    {

        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
            _receiver,
            _token,
            _amount,
            address(0)
        );

        // Get the fee required to send the message
        uint256 fees = s_router.getFee(
            _destinationChainSelector,
            evm2AnyMessage
        );

        if (fees > address(this).balance)
            revert NotEnoughBalance(address(this).balance, fees);

        // approve the Router to spend tokens on contract's behalf. It will spend the amount of the given token
        IERC20(_token).approve(address(s_router), _amount);

        // Send the message through the router and store the returned message ID
        messageId = s_router.ccipSend{value: fees}(
            _destinationChainSelector,
            evm2AnyMessage
        );

        // Emit an event with message details
        emit TokensTransferred(
            messageId,
            _destinationChainSelector,
            _receiver,
            _token,
            _amount,
            address(0),
            fees
        );

        // Return the message ID
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
}





