// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";

import "./PaymentSplitter.sol";

contract PaymentSplitterFactory is Ownable {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.UintSet;

    uint256 public nextPaymentSplitterId;
    mapping(uint256 => PaymentSplitter) public paymentSplitters;

    mapping(address => EnumerableSet.UintSet) accountPaymentSplitters;

    /**
     ** Users
     */

    event CreatePaymentSplitterLog(
        uint256 indexed id,
        address indexed paymentSplitterAddress
    );

    function createPaymentSplitter(
        address[] calldata _payees,
        uint256[] calldata _shares
    ) external onlyOwner returns (uint256, address) {
        uint256 nextId = nextPaymentSplitterId;
        nextPaymentSplitterId = nextId.add(1);

        for (uint256 i = 0; i < _payees.length; i++) {
            accountPaymentSplitters[_payees[i]].add(nextId);
        }

        PaymentSplitter paymentSplitter = new PaymentSplitter(_payees, _shares);
        paymentSplitters[nextId] = paymentSplitter;

        emit CreatePaymentSplitterLog(
            nextPaymentSplitterId,
            address(paymentSplitter)
        );

        return (nextId, address(paymentSplitter));
    }

    function release(
        uint256 _paymentSplitterId,
        IERC20 _token,
        address _account
    ) external {
        paymentSplitters[_paymentSplitterId].release(_token, _account);
    }

    function release(
        uint256 _paymentSplitterId,
        IERC20[] calldata _tokens,
        address[] calldata _accounts
    ) external {
        paymentSplitters[_paymentSplitterId].release(_tokens, _accounts);
    }

    function release(uint256 _paymentSplitterId, IERC20[] calldata _tokens)
        external
    {
        paymentSplitters[_paymentSplitterId].release(_tokens);
    }

    function getPending(
        uint256 _paymentSplitterId,
        IERC20 _token,
        address _account
    ) external view returns (uint256) {
        return
            paymentSplitters[_paymentSplitterId].getPending(_token, _account);
    }

    function getPayees(uint256 _paymentSplitterId)
        external
        view
        returns (address[] memory)
    {
        return paymentSplitters[_paymentSplitterId].getPayees();
    }

    function getPayeesLength(uint256 _paymentSplitterId)
        external
        view
        returns (uint256)
    {
        return paymentSplitters[_paymentSplitterId].getPayeesLength();
    }

    function getPayeesByIndex(uint256 _paymentSplitterId, uint256 _index)
        external
        view
        returns (address)
    {
        return paymentSplitters[_paymentSplitterId].getPayeesByIndex(_index);
    }

    function getPaymentSplittersLength(address _account)
        external
        view
        returns (uint256)
    {
        return accountPaymentSplitters[_account].length();
    }

    function getUserRoyaltyReceiversByIndex(address _account, uint256 _index)
        external
        view
        returns (uint256, address)
    {
        uint256 royaltyReceiverId = accountPaymentSplitters[_account].at(
            _index
        );

        return (
            royaltyReceiverId,
            address(paymentSplitters[royaltyReceiverId])
        );
    }
}
