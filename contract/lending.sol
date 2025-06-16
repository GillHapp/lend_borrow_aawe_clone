// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import {aToken} from "./aToken.sol";

contract Lending is Ownable {
    uint256 public rewardRate = 1;
    aToken public atoken;
    AggregatorV3Interface internal priceFeed;

    struct UserBalance {
        uint256 ethDeposited;
        uint256 aTokenMinted;
        uint256 depositTimestamp;
        uint256 unclaimedRewards;
    }

    mapping(address => UserBalance) public balances;

    constructor(address _atoken,address _priceFeed) Ownable(msg.sender) {
        atoken = aToken(_atoken);
         priceFeed = AggregatorV3Interface(_priceFeed);
    }

    function depositETH() external payable {
        require(msg.value > 0, "Send some ETH");
        uint256 gweiAmount = msg.value / 1 gwei;
        require(gweiAmount > 0, "Send at least 1 gwei");

        UserBalance storage user = balances[msg.sender];

        if (user.ethDeposited > 0) {
            uint256 pendingReward = calculateReward(msg.sender);
            user.unclaimedRewards += pendingReward;
        }

        user.ethDeposited += msg.value;
        user.aTokenMinted += gweiAmount;
        user.depositTimestamp = block.timestamp;

        atoken.mint(msg.sender, gweiAmount * 1e18);
    }

 function calculateReward(address userAddr) public view returns (uint256) {
    UserBalance memory user = balances[userAddr];
    require(user.ethDeposited > 0, "No deposit");

    uint256 timeElapsed = block.timestamp - user.depositTimestamp;

    // Require full 30-hour interval to apply reward
    if (timeElapsed < 30 hours) {
        return user.unclaimedRewards; // no new reward yet
    }

    uint256 intervals = timeElapsed / (30 hours);
    uint256 ethInGwei = user.ethDeposited / 1 gwei;
    uint256 currentScale = getLatestEthUsdPrice();

    uint256 reward = (ethInGwei * intervals * rewardRate) / currentScale;

    return reward + user.unclaimedRewards;
}


    function getContractEthBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function withdrawAllETH() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    function getAPR() public view returns (uint256) {
        uint256 intervalsPerYear = (365 * 24) / 30;
        uint256 currentScale = getLatestEthUsdPrice();

        uint256 apr = (rewardRate * intervalsPerYear * 10000) / currentScale;
        return apr;
    }

    function getAPY() public view returns (uint256) {
        uint256 apr = getAPR();

        uint256 daysInYear = 365;
        uint256 base = 1e6;
        uint256 ratePerDay = (apr * base) / (daysInYear * 10000);

        uint256 apy = base;
        for (uint256 i = 0; i < daysInYear; i++) {
            apy = (apy * (base + ratePerDay)) / base;
        }

        return (apy - base) * 10000 / base;
    }

   function redeemaToken() external {
    UserBalance storage user = balances[msg.sender];
    require(user.ethDeposited > 0, "No deposit");

    uint256 pendingReward = calculateReward(msg.sender);
    user.unclaimedRewards += pendingReward;

    uint256 totalGwei = user.aTokenMinted + user.unclaimedRewards;
    uint256 totalETHToReturn = (totalGwei * 1 gwei);

    require(address(this).balance >= totalETHToReturn, "Insufficient contract balance");

    // Burn aTokens
atoken.burn(msg.sender, user.aTokenMinted * 1e18);

    // Send ETH back
    payable(msg.sender).transfer(totalETHToReturn);

    // Reset user balance
    delete balances[msg.sender];

    // emit Redeemed(msg.sender, totalETHToReturn, totalGwei);
}

 function getLatestEthUsdPrice() public view returns (uint256) {
    (, int256 price,,,) = priceFeed.latestRoundData();
    return uint256(price)/10**8; // 8 decimals
}

}
