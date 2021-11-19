// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestERC20 is ERC20 {
    constructor() ERC20("Some Test token", "TST") { }

    function mint(address _recipient, uint256 _amount) external {
        _mint(_recipient, _amount);
    }
}
