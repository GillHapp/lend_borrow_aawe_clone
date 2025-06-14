// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;


import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import {aToken} from "./aToken.sol";

contract Lending is Ownable{
     uint256 public rewardRate = 1; 
    aToken public atoken;
     uint256 public scale = 10000; 
    AggregatorV3Interface internal priceFeed;
    struct UserBalance {
        uint256 ethDeposited;      // in wei
        uint256 aTokenMinted;      // in aToken units
        uint256 depositTimestamp;  // timestamp of latest deposit
    }

    mapping(address => UserBalance) public balances;

    constructor(address _atoken, address _priceFeed) Ownable(msg.sender) {
        atoken = aToken(_atoken);
        priceFeed = AggregatorV3Interface(_priceFeed);
}



    /// @notice Deposit ETH and receive aTokens at a 1 gwei = 1 aToken ratio
    function depositETH() external payable {
        require(msg.value > 0, "Send some ETH");

        uint256 gweiAmount = msg.value / 1 gwei;
        require(gweiAmount > 0, "Send at least 1 gwei");

        UserBalance storage user = balances[msg.sender];

        // If first deposit, set the timestamp
        if (user.ethDeposited == 0) {
            user.depositTimestamp = block.timestamp;
        }

        user.ethDeposited += msg.value;
        user.aTokenMinted += gweiAmount;
        atoken.mint(msg.sender, gweiAmount * 1e18);
    }

    /// @notice View function to calculate user's reward based on amount * time
   function calculateReward(address userAddr) public view returns (uint256) {
    UserBalance memory user = balances[userAddr];
    require(user.ethDeposited > 0, "No deposit");

    uint256 timeElapsed = block.timestamp - user.depositTimestamp;
    uint256 ethInGwei = user.ethDeposited / 1 gwei; // convert wei to gwei
    uint256 minutesElapsed = timeElapsed / 1 minutes;
    uint256 scale1 = getLatestEthUsdPrice();
    uint256 reward = (ethInGwei * minutesElapsed * rewardRate) / scale1;
    // uint256 scale = scale1;
    return reward;
}

    function getLatestEthUsdPrice() public view returns (uint256) {
    (, int256 price,,,) = priceFeed.latestRoundData();
    return uint256(price)/10**8; // 8 decimals
}

    function getContractEthBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function withdrawAllETH() external onlyOwner {
    payable(msg.sender).transfer(address(this).balance);
}

}
    // receive() external payable {}
// 0xE634415C9931197f571AF6c7cc65853Aea3C64a1
// 0x57c29243A1C0866F4f3D136E2E85e1a90AFB79A2
