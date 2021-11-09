// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./PaymentSplitterV1.sol";

contract PaymentSplitterFactory is Ownable {
    mapping(address => bool) public isPaymentSplitter;
    mapping(address => PaymentSplitter[]) private accountPaymentSplitters;

    /**
     ** Users
     */

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
        IERC20[] calldata _tokens,
        address[] calldata _accounts
    ) external {
        require(isPaymentSplitter[_paymentSplitter], "Not a payment splitter");

        for (uint256 i = 0; i < _tokens.length; i++) {
            for (uint256 j = 0; j < _accounts.length; j++) {
                uint256 amount = PaymentSplitter(_paymentSplitter).release(
                    _tokens[i],
                    _accounts[j]
                );

                emit ReleaseLog(
                    PaymentSplitter(_paymentSplitter),
                    _tokens[i],
                    _accounts[j],
                    amount
                );
            }
        }
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
