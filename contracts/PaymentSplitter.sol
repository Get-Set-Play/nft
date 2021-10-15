// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// Based on: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/finance/PaymentSplitter.sol

contract PaymentSplitter {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    event PayeeAdded(address account, uint256 shares);
    event PaymentReleased(
        IERC20 indexed token,
        address account,
        uint256 amount
    );

    address[] private payees;

    uint256 public totalShares;
    mapping(address => uint256) private shares;

    mapping(IERC20 => uint256) public totalReleased;
    mapping(IERC20 => mapping(address => uint256)) public released;

    constructor(address[] memory _payees, uint256[] memory _shares) payable {
        require(_payees.length > 0, "No payees");
        require(_payees.length == _shares.length, "Length mismatch");

        for (uint256 i = 0; i < _payees.length; i++) {
            require(_payees[i] != address(0), "Account is the zero address");
            require(_shares[i] > 0, "Shares are 0");
            require(shares[_payees[i]] == 0, "Account already has shares");

            payees.push(_payees[i]);
            shares[_payees[i]] = _shares[i];
            totalShares = totalShares.add(_shares[i]);

            emit PayeeAdded(_payees[i], _shares[i]);
        }
    }

    function release(IERC20 _token, address _account) public {
        uint256 accountShares = shares[_account];
        require(accountShares > 0, "Account has no shares");

        uint256 tokenTotalReleased = totalReleased[_token];
        uint256 totalReceived = _token.balanceOf(address(this)).add(
            tokenTotalReleased
        );

        uint256 accountTokenReleased = released[_token][_account];
        uint256 payment = totalReceived.mul(accountShares) /
            totalShares -
            accountTokenReleased;

        require(payment > 0, "Account is not due payment");

        released[_token][_account] = accountTokenReleased.add(payment);
        totalReleased[_token] = tokenTotalReleased.add(payment);

        _token.safeTransfer(_account, payment);

        emit PaymentReleased(_token, _account, payment);
    }

    function release(IERC20[] memory _tokens, address[] memory _accounts)
        public
    {
        for (uint256 i = 0; i < _tokens.length; i++) {
            for (uint256 j = 0; j < _accounts.length; j++) {
                release(_tokens[i], _accounts[j]);
            }
        }
    }

    function release(IERC20[] calldata _tokens) external {
        release(_tokens, payees);
    }

    function getPending(IERC20 _token, address _account)
        external
        view
        returns (uint256)
    {
        uint256 totalReceived = _token.balanceOf(address(this)).add(
            totalReleased[_token]
        );

        uint256 pending = totalReceived.mul(shares[_account]) /
            totalShares -
            released[_token][_account];

        return pending;
    }

    function getPayees() external view returns (address[] memory) {
        return payees;
    }

    function getPayeesLength() external view returns (uint256) {
        return payees.length;
    }

    function getPayeesByIndex(uint256 _index) external view returns (address) {
        return payees[_index];
    }
}
