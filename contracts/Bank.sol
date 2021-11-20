// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./lib/InterestAccount.sol";
import "./interfaces/IPriceOracle.sol";
import "./interfaces/IBank.sol";

contract Bank is IBank {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Address for address payable;
    using InterestAccount for InterestAccount.Account;

    uint256 internal constant DEPOSIT_INTEREST = 3;
    uint256 internal constant DEBT_INTEREST = 5;

    uint256 internal constant SCALE = 1e4;
    IERC20 internal constant PSEUDO_ETH =
        IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    IERC20 public immutable hakToken;
    IPriceOracle public immutable priceOracle;

    struct DebtAccount {
        uint256 debt;
        uint256 interest;
        uint256 lastInterestBlock;
    }

    // wallet => token => Account
    mapping(address => mapping(address => InterestAccount.Account)) internal depositAccounts;
    mapping(address => InterestAccount.Account) internal ethDebtAccounts;

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
        InterestAccount.Account storage depositAccount
            = depositAccounts[msg.sender][_token];
        depositAccount.updateInterest(DEPOSIT_INTEREST, _getBlockNumber());
        depositAccount.balance = depositAccount.balance.add(_amount);
        emit Deposit(msg.sender, _token, _amount);
        return true;
    }


    function withdraw(address _token, uint256 _amount)
        external override returns (uint256)
    {

        InterestAccount.Account storage depositAccount
            = depositAccounts[msg.sender][_token];
        uint256 depositBalance = getBalance(_token);

        if (_token == address(PSEUDO_ETH)) {
            if(_amount == 0) {
                payable(msg.sender).sendValue(depositBalance);
                depositAccount.decreaseBalanceBy(depositBalance, DEPOSIT_INTEREST, _getBlockNumber());
            } else {
                require(depositBalance >= _amount, "Bank: insufficient HAK Balance");
                payable(msg.sender).sendValue(_amount);
                depositAccount.decreaseBalanceBy(_amount, DEPOSIT_INTEREST, _getBlockNumber());
            }  
        } else if (_token == address(hakToken)) {
            if(_amount == 0) {
                hakToken.safeTransfer(msg.sender, depositBalance);
                depositAccount.decreaseBalanceBy(depositBalance, DEPOSIT_INTEREST, _getBlockNumber());
            } else {
                require(depositBalance >= _amount, "Bank: insufficient HAK Balance");
                hakToken.safeTransfer(msg.sender, _amount);
                depositAccount.decreaseBalanceBy(_amount, DEPOSIT_INTEREST, _getBlockNumber());
            }
        } else {
            revert("Bank: Unsupported token");
        }
        emit Withdraw(msg.sender, _token, _amount);
        return _amount == 0 ? depositBalance : _amount;
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
        public view override returns (uint256)
    {
        return depositAccounts[msg.sender][_token]
            .getTotalBalance(DEPOSIT_INTEREST, _getBlockNumber());
    }

    function getCollateralRatio(address _token, address _account)
        external view override returns (uint256)
    {
        require(_token == address(hakToken), "Bank: Invalid collateral");
        uint256 assetBalance = depositAccounts[_account][_token]
            .getTotalBalance(DEPOSIT_INTEREST, _getBlockNumber());
        uint256 debtBalance = ethDebtAccounts[_account]
            .getTotalBalance(DEBT_INTEREST, _getBlockNumber());
        if (debtBalance == 0) return type(uint256).max;
        return assetBalance.mul(SCALE).div(debtBalance);
    }

    function _getBlockNumber() internal virtual view returns (uint256) {
        return block.number;
    }
}
