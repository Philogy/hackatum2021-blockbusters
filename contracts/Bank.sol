// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./lib/InterestAccount.sol";
import "./interfaces/IPriceOracle.sol";
import "./interfaces/IBank.sol";

contract Bank is IBank, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Address for address payable;
    using InterestAccount for InterestAccount.Account;

    uint256 internal constant DEPOSIT_INTEREST = 3;
    uint256 internal constant DEBT_INTEREST = 5;
    uint256 internal constant MIN_COLLAT_RATIO = 15000; // 150%

    uint256 internal constant SCALE = 1e4;
    IERC20 internal constant PSEUDO_ETH =
        IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    IERC20 public immutable hakToken;
    IPriceOracle public immutable priceOracle;

    // wallet => token => Account
    mapping(address => mapping(address => InterestAccount.Account)) internal depositAccounts;
    mapping(address => InterestAccount.Account) internal ethDebtAccounts;

    constructor(address _priceOracle, address _hakToken) ReentrancyGuard() {
        priceOracle = IPriceOracle(_priceOracle);
        hakToken = IERC20(_hakToken);
    }

    function deposit(address _token, uint256 _amount)
        external payable override nonReentrant returns (bool)
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
        depositAccount.increaseBalanceBy(_amount, DEPOSIT_INTEREST, _getBlockNumber());
        emit Deposit(msg.sender, _token, _amount);
        return true;
    }


    function withdraw(address _token, uint256 _amount)
        external override nonReentrant returns (uint256)
    {
        InterestAccount.Account storage depositAccount
            = depositAccounts[msg.sender][_token];
        uint256 depositedBalance = getBalance(_token);
        if(_amount == 0) _amount = depositedBalance;
        require(depositedBalance >= _amount, "Bank: Insufficient Balance");
        depositAccount.decreaseBalanceBy(_amount, DEPOSIT_INTEREST, _getBlockNumber());
        if (_token == address(PSEUDO_ETH)) {
            emit Withdraw(msg.sender, _token, _amount);
            payable(msg.sender).sendValue(_amount);
        } else if (_token == address(hakToken)) {
            hakToken.safeTransfer(msg.sender, _amount);
            emit Withdraw(msg.sender, _token, _amount);
        } else {
            revert("Bank: Unsupported token");
        }
        return _amount;
    }

    function borrow(address _token, uint256 _amount)
        external override nonReentrant returns (uint256)
    {
        require(_token == address(PSEUDO_ETH), "Bank: Can only borrow ETH");
        uint256 assetBalance = getBalance(address(hakToken));
        require(assetBalance > 0, "Bank: No collateral");
        uint256 assetEthValue = _hakToEth(assetBalance);
        uint256 maxDebt = assetEthValue.mul(SCALE).div(MIN_COLLAT_RATIO);
        uint256 existingDebt = _getDebtBalanceOf(msg.sender);
        uint256 maxBorrow = maxDebt.sub(existingDebt, "Bank: Below min collat ratio");
        require(_amount <= maxBorrow, "Bank: Attempted overdraft");
        if (_amount == 0) _amount = maxBorrow;
        ethDebtAccounts[msg.sender]
            .increaseBalanceBy(_amount, DEBT_INTEREST, _getBlockNumber());
        emit Borrow(
            msg.sender,
            address(PSEUDO_ETH),
            _amount,
            assetEthValue.mul(SCALE).div(_amount.add(existingDebt))
        );
        payable(msg.sender).sendValue(_amount);
        return getCollateralRatio(address(hakToken), msg.sender);
    }

    function repay(address _token, uint256 _amount)
        external payable override nonReentrant returns (uint256)
    {

    }

    function liquidate(address _token, address _account)
        external payable override nonReentrant returns (bool)
    {
        require(
            getCollateralRatio(_token, _account) < MIN_COLLAT_RATIO,
            "Bank: Cannot liquidate account"
        );
        require(_account != msg.sender, "Bank: Attempted self liquidation");
        uint256 debtBalance = _getDebtBalanceOf(_account);
        uint256 refund = msg.value.sub(debtBalance, "Bank: Insufficient repayment");
        ethDebtAccounts[_account].reset();
        InterestAccount.Account storage collateralAccount =
            depositAccounts[_account][_token];
        uint256 liquidatedDeposit = collateralAccount
            .getTotalBalance(DEPOSIT_INTEREST, _getBlockNumber());
        collateralAccount.reset();
        hakToken.safeTransfer(msg.sender, liquidatedDeposit);
        emit Liquidate(
            msg.sender,
            _account,
            _token,
            liquidatedDeposit,
            refund
        );
        payable(msg.sender).sendValue(refund);
        return true;
    }

    function getBalance(address _token)
        public view override returns (uint256)
    {
        return depositAccounts[msg.sender][_token]
            .getTotalBalance(DEPOSIT_INTEREST, _getBlockNumber());
    }

    function getCollateralRatio(address _token, address _account)
        public view override returns (uint256)
    {
        require(_token == address(hakToken), "Bank: Invalid collateral");
        uint256 assetBalance = depositAccounts[_account][_token]
            .getTotalBalance(DEPOSIT_INTEREST, _getBlockNumber());
        if (assetBalance == 0) return 0;
        uint256 debtBalance = _getDebtBalanceOf(_account);
        if (debtBalance == 0) return type(uint256).max;
        return _hakToEth(assetBalance).mul(SCALE).div(debtBalance);
    }

    function _hakToEth(uint256 _hakAmount) internal view returns (uint256) {
        uint256 hakToEthPrice = priceOracle.getVirtualPrice(address(hakToken));
        return _hakAmount.mul(hakToEthPrice).div(1e18);
    }

    function _getDebtBalanceOf(address _account)
        internal view returns (uint256)
    {
        return ethDebtAccounts[_account].getTotalBalance(DEBT_INTEREST, _getBlockNumber());
    }

    function _getBlockNumber() internal virtual view returns (uint256) {
        return block.number;
    }
}
