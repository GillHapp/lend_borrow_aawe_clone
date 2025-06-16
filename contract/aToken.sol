// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
contract aToken is ERC20 {
    constructor() ERC20("Lending aToken", "aTOK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address to,uint256 amount) external {
        _burn(to, amount);
    }
}
