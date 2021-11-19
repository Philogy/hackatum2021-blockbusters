// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interfaces/IPriceOracle.sol";
import "./interfaces/IBank.sol";

contract Bank is IBank {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IERC20 internal constant PSEUDO_ETH =
        IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    IERC20 public immutable hakToken;
    IPriceOracle public immutable priceOracle;

    mapping(address => mapping(address => Account)) internal accounts;

    constructor(address _priceOracle, address _hakToken) {
        priceOracle = IPriceOracle(_priceOracle);
        hakToken = IERC20(_hakToken);
    }

    function deposit(address _token, uint256 _amount)
        external payable override returns (bool)
    {
        if (_token == address(PSEUDO_ETH)) {
            require(msg.value > 0, "Bank: Deposit of 0");
            require(msg.value == _amount, "Bank: Amount mismatch");
        } else if (_token == address(hakToken)) {
            require(msg.value == 0, "Bank: Attempted ETH deposit");
            hakToken.safeTransferFrom(msg.sender, address(this), _amount);
        } else {
            revert("Bank: Unsupported token");
        }
        Account storage account = accounts[_token][msg.sender];
        _updateInterest(account);
        account.deposit = account.deposit.add(_amount);
        emit Deposit(msg.sender, _token, _amount);
        return true;
    }

    function withdraw(address _token, uint256 _amount)
        external override returns (uint256)
    {

    }

    function borrow(address _token, uint256 _amount)
        external override returns (uint256)
    {

    }

    function repay(address _token, uint256 _amount)
        external payable override returns (uint256)
    {

    }

    function liquidate(address _token, address _account)
        external payable override returns (bool)
    {

    }

    function getBalance(address _token)
        external view override returns (uint256)
    {

    }

    function getCollateralRatio(address _token, address _account)
        external view override returns (uint256)
    {

    }

    function _updateInterest(Account storage _account) internal {
        uint256 passedBlocks = block.number.sub(_account.lastInterestBlock);
        uint256 newInterest = _account.deposit * 3 * passedBlocks / 1e4;
        _account.lastInterestBlock = block.number;
        _account.interest = _account.interest.add(newInterest);
    }
}
