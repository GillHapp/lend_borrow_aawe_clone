// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;


import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import {aToken} from "./aToken.sol";

contract Lending is Ownable{
     uint256 public rewardRate = 1; 
    aToken public atoken;
     uint256 public scale = 2500; 
    AggregatorV3Interface internal priceFeed;
    struct UserBalance {
        uint256 ethDeposited;      // in wei
        uint256 aTokenMinted;      // in aToken units
        uint256 depositTimestamp;  // timestamp of latest deposit
         uint256 unclaimedRewards;
    }

    mapping(address => UserBalance) public balances;

    constructor(address _atoken /*address _priceFeed*/) Ownable(msg.sender) {
        atoken = aToken(_atoken);
        // priceFeed = AggregatorV3Interface(_priceFeed);
}



    /// @notice Deposit ETH and receive aTokens at a 1 gwei = 1 aToken ratio
function depositETH() external payable {
    require(msg.value > 0, "Send some ETH");
    uint256 gweiAmount = msg.value / 1 gwei;
    require(gweiAmount > 0, "Send at least 1 gwei");

    UserBalance storage user = balances[msg.sender];

    // First: accumulate previous rewards before updating deposit
    if (user.ethDeposited > 0) {
        uint256 pendingReward = calculateReward(msg.sender);
        user.unclaimedRewards += pendingReward;
    }

    // Update deposit and timestamp
    user.ethDeposited += msg.value;
    user.aTokenMinted += gweiAmount;
    user.depositTimestamp = block.timestamp; // reset timestamp to now

    // Mint aTokens
    atoken.mint(msg.sender, gweiAmount * 1e18);
}


    /// @notice View function to calculate user's reward based on amount * time
function calculateReward(address userAddr) public view returns (uint256) {
    UserBalance memory user = balances[userAddr];
    require(user.ethDeposited > 0, "No deposit");

    uint256 timeElapsed = block.timestamp - user.depositTimestamp;
    uint256 ethInGwei = user.ethDeposited / 1 gwei;
    uint256 fiveMinIntervals = timeElapsed / (30 hours);

    uint256 reward = (ethInGwei * fiveMinIntervals * rewardRate) / scale;

    return reward + user.unclaimedRewards;
}



//     function getLatestEthUsdPrice() public view returns (uint256) {
//     (, int256 price,,,) = priceFeed.latestRoundData();
//     return uint256(price)/10**8; // 8 decimals
// }

    function getContractEthBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function withdrawAllETH() external onlyOwner {
    payable(msg.sender).transfer(address(this).balance);
}

/// @notice Returns the current Annual Percentage Rate (APR) as a percentage with 2 decimals (e.g., 1314 = 13.14%)
function getAPR() public view returns (uint256) {
    // Number of 30-hour intervals in a year: 365 days * 24 hours / 30
    uint256 intervalsPerYear = (365 * 24) / 30; // = 292 intervals approx
    uint256 apr = (rewardRate * intervalsPerYear * 10000) / scale; // 2 decimals
    return apr; // e.g., 1200 = 12.00%
}



/// @notice Returns the current Annual Percentage Yield (APY) with daily compounding (e.g., 1404 = 14.04%)
function getAPY() public view returns (uint256) {
    uint256 apr = getAPR(); // APR with 2 decimals, e.g., 1168 = 11.68%

    uint256 daysInYear = 365;
    uint256 base = 1e6; // For precision
    uint256 ratePerDay = (apr * base) / (daysInYear * 10000); // Convert 2-decimal % to fixed-point daily rate

    uint256 apy = base;
    for (uint256 i = 0; i < daysInYear; i++) {
        apy = (apy * (base + ratePerDay)) / base;
    }

    return (apy - base) * 10000 / base; // APY returned with 2 decimals
}



}




    // receive() external payable {}
// 0xE634415C9931197f571AF6c7cc65853Aea3C64a1
// 0x57c29243A1C0866F4f3D136E2E85e1a90AFB79A2
