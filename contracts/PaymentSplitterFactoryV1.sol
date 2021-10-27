// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";

import "./PaymentSplitterV1.sol";

contract PaymentSplitterFactory is Ownable {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.UintSet;

    mapping(address => bool) public isPaymentSplitter;
    mapping(address => PaymentSplitter[]) private accountPaymentSplitters;

    /**
     ** Users
     */

    modifier onlyPaymentSplitter(address _paymentSplitter) {
        require(isPaymentSplitter[_paymentSplitter], "Not a payment splitter");
        _;
    }

    event CreateLog(
        PaymentSplitter indexed paymentSplitter,
        address[] payees,
        uint256[] shares
    );

    function create(address[] calldata _payees, uint256[] calldata _shares)
        external
        onlyOwner
        returns (PaymentSplitter)
    {
        PaymentSplitter paymentSplitter = new PaymentSplitter(_payees, _shares);

        isPaymentSplitter[address(paymentSplitter)] = true;

        for (uint256 i = 0; i < _payees.length; i++) {
            accountPaymentSplitters[_payees[i]].push(paymentSplitter);
        }

        emit CreateLog(paymentSplitter, _payees, _shares);

        return paymentSplitter;
    }

    event ReleaseLog(
        PaymentSplitter indexed paymentSplitter,
        IERC20 indexed token,
        address indexed account,
        uint256 amount
    );

    function release(
        address _paymentSplitter,
        IERC20[] memory _tokens,
        address[] memory _accounts
    ) public onlyPaymentSplitter(_paymentSplitter) {
        for (uint256 i = 0; i < _tokens.length; i++) {
            for (uint256 j = 0; j < _accounts.length; j++) {
                uint256 amount = PaymentSplitter(_paymentSplitter).release(
                    _tokens[i],
                    _accounts[i]
                );

                emit ReleaseLog(
                    PaymentSplitter(_paymentSplitter),
                    _tokens[i],
                    _accounts[i],
                    amount
                );
            }
        }
    }

    function getPending(
        address _paymentSplitter,
        IERC20 _token,
        address _account
    ) external view onlyPaymentSplitter(_paymentSplitter) returns (uint256) {
        return PaymentSplitter(_paymentSplitter).getPending(_token, _account);
    }

    function getPayees(address _paymentSplitter)
        public
        view
        onlyPaymentSplitter(_paymentSplitter)
        returns (address[] memory)
    {
        return PaymentSplitter(_paymentSplitter).getPayees();
    }

    function getPayeesLength(address _paymentSplitter)
        external
        view
        onlyPaymentSplitter(_paymentSplitter)
        returns (uint256)
    {
        return PaymentSplitter(_paymentSplitter).getPayeesLength();
    }

    function getPayeesByIndex(address _paymentSplitter, uint256 _index)
        external
        view
        onlyPaymentSplitter(_paymentSplitter)
        returns (address)
    {
        return PaymentSplitter(_paymentSplitter).getPayeesByIndex(_index);
    }

    function getPaymentSplitters(address _account)
        external
        view
        returns (PaymentSplitter[] memory)
    {
        return accountPaymentSplitters[_account];
    }

    function getPaymentSplittersLength(address _account)
        external
        view
        returns (uint256)
    {
        return accountPaymentSplitters[_account].length;
    }

    function getPaymentSplittersByIndex(address _account, uint256 _index)
        external
        view
        returns (PaymentSplitter)
    {
        return accountPaymentSplitters[_account][_index];
    }
}
