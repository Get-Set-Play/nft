// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";

// Based on: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/finance/PaymentSplitter.sol

contract PrizePool is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    // Shares by settlement position.
    uint256[] private distribution;
    uint256 public totalShares;

    // Participants addresses and their shares after settlement.
    EnumerableSet.AddressSet private participants;
    mapping(address => uint256) public shares;

    // Track how many funds have been released to each participant and in total.
    mapping(IERC20 => uint256) public totalReleased;
    mapping(IERC20 => mapping(address => uint256)) public released;

    function initialize(
        address[] calldata _participants,
        uint256[] calldata _distribution
    ) external onlyOwner {
        require(_participants.length > 0, "No participants");
        require(
            _participants.length == _distribution.length,
            "Length mismatch"
        );
        require(participants.length() == 0, "Already initialized");

        for (uint256 i = 0; i < _participants.length; i++) {
            require(
                _participants[i] != address(0),
                "Account is the zero address"
            );
            require(_distribution[i] > 0, "Shares are 0");

            bool added = participants.add(_participants[i]);
            require(added, "Duplicate account");

            distribution.push(_distribution[i]);
            totalShares = totalShares.add(_distribution[i]);
        }
    }

    function settle(address[] calldata _participants) external onlyOwner {
        require(
            _participants.length == participants.length(),
            "Length mismatch"
        );

        for (uint256 i = 0; i < _participants.length; i++) {
            require(
                participants.contains(_participants[i]),
                "Not a participant"
            );
            require(shares[_participants[i]] == 0, "Duplicate account");

            shares[_participants[i]] = distribution[i];
        }
    }

    event ReleaseLog(
        IERC20 indexed token,
        address indexed account,
        uint256 amount
    );

    function release(IERC20 _token, address _account) private {
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

        emit ReleaseLog(_token, _account, payment);
    }

    function release(IERC20[] calldata _tokens, address[] calldata _accounts)
        external
    {
        for (uint256 i = 0; i < _tokens.length; i++) {
            for (uint256 j = 0; j < _accounts.length; j++) {
                release(_tokens[i], _accounts[j]);
            }
        }
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

    function getDistribution() external view returns (uint256[] memory) {
        return distribution;
    }

    function getDistributionLength() external view returns (uint256) {
        return distribution.length;
    }

    function getDistributionByIndex(uint256 _index)
        external
        view
        returns (uint256)
    {
        return distribution[_index];
    }

    function getParticipants() external view returns (address[] memory) {
        uint256 participantsLength = participants.length();

        address[] memory result = new address[](participantsLength);
        for (uint256 i = 0; i < participantsLength; i++) {
            result[i] = participants.at(i);
        }
        return result;
    }

    function getParticipantsLength() external view returns (uint256) {
        return participants.length();
    }

    function getParticipantsByIndex(uint256 _index)
        external
        view
        returns (address)
    {
        return participants.at(_index);
    }
}
