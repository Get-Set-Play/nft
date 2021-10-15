// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155Holder.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Marketplace is ERC721Holder, ERC1155Holder, ReentrancyGuard, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public tradeFeeMultiplier = 500; // Multiplied by 10000

    mapping(address => bool) public whitelistedCurrencies;

    enum CollectionType {
        NONE,
        ERC721,
        ERC1155
    }

    struct Ask {
        uint256 tokenId;
        uint256 amount;
        address asker;
        IERC20 currency;
        uint256 currencyAmountPerUnit;
        uint256 deadlineTimestamp;
    }

    struct Bid {
        uint256 tokenId;
        uint256 amount;
        address bidder;
        IERC20 currency;
        uint256 currencyAmountPerUnit;
        uint256 deadlineTimestamp;
    }

    struct RoyaltyInfo {
        address to;
        uint256 multiplier; // Multiplied by 10000
    }

    struct CollectionData {
        CollectionType collectionType;
        uint256 nextAskId;
        mapping(uint256 => Ask) asks;
        uint256 nextBidId;
        mapping(uint256 => Bid) bids;
        mapping(uint256 => RoyaltyInfo) royalty;
    }

    mapping(address => CollectionData) public collectionData;

    /**
     ** Users
     */

    event CreateAskLog(
        address indexed userAddress,
        address indexed contractAddress,
        uint256 indexed askId,
        uint256 tokenId,
        uint256 amount,
        address currency,
        uint256 currencyAmountPerUnit,
        uint256 deadlineTimestamp
    );

    function createAsk(
        address _contractAddress,
        uint256 _tokenId,
        uint256 _amount,
        IERC20 _currency,
        uint256 _currencyAmountPerUnit,
        uint256 _deadlineTimestamp
    ) public nonReentrant {
        require(_currencyAmountPerUnit > 0, "Zero currency amount per unit");
        require(_deadlineTimestamp > block.timestamp, "Invalid deadline");
        require(
            whitelistedCurrencies[address(_currency)],
            "Currency not whitelisted"
        );

        CollectionType collectionType = collectionData[_contractAddress]
            .collectionType;
        require(
            collectionType != CollectionType.NONE,
            "Contract not whitelisted"
        );

        uint256 amount = 1;
        if (collectionType == CollectionType.ERC1155) {
            require(_amount > 0, "Zero amount");
            amount = _amount;
        }

        uint256 askId = collectionData[_contractAddress].nextAskId;
        collectionData[_contractAddress].nextAskId = askId.add(1);

        collectionData[_contractAddress].asks[askId] = Ask({
            tokenId: _tokenId,
            amount: amount,
            asker: msg.sender,
            currency: _currency,
            currencyAmountPerUnit: _currencyAmountPerUnit,
            deadlineTimestamp: _deadlineTimestamp
        });

        if (collectionType == CollectionType.ERC721) {
            IERC721(_contractAddress).safeTransferFrom(
                msg.sender,
                address(this),
                _tokenId
            );
        } else {
            IERC1155(_contractAddress).safeTransferFrom(
                msg.sender,
                address(this),
                _tokenId,
                amount,
                ""
            );
        }

        emit CreateAskLog(
            msg.sender,
            _contractAddress,
            askId,
            _tokenId,
            amount,
            address(_currency),
            _currencyAmountPerUnit,
            _deadlineTimestamp
        );
    }

    event UpdateAskDeadlineLog(
        address indexed contractAddress,
        uint256 indexed askId,
        uint256 deadlineTimestamp
    );

    function updateAskDeadline(
        address _contractAddress,
        uint256 _askId,
        uint256 _deadlineTimestamp
    ) public nonReentrant {
        require(_deadlineTimestamp > block.timestamp, "Invalid deadline");
        require(
            msg.sender == collectionData[_contractAddress].asks[_askId].asker,
            "Only asker"
        );

        collectionData[_contractAddress]
            .asks[_askId]
            .deadlineTimestamp = _deadlineTimestamp;

        emit UpdateAskDeadlineLog(_contractAddress, _askId, _deadlineTimestamp);
    }

    event CancelAskLog(
        address indexed contractAddress,
        uint256 indexed askId,
        uint256 amount
    );

    function cancelAsk(
        address _contractAddress,
        uint256 _askId,
        uint256 _amount
    ) public nonReentrant {
        require(_amount > 0, "Zero amount");

        Ask memory ask = collectionData[_contractAddress].asks[_askId];

        require(msg.sender == ask.asker, "Only asker");

        uint256 newAmount = ask.amount.sub(_amount, "Not enough available");
        if (newAmount == 0) {
            delete collectionData[_contractAddress].asks[_askId];
        } else {
            collectionData[_contractAddress].asks[_askId].amount = newAmount;
        }

        if (
            collectionData[_contractAddress].collectionType ==
            CollectionType.ERC721
        ) {
            IERC721(_contractAddress).safeTransferFrom(
                address(this),
                ask.asker,
                ask.tokenId
            );
        } else {
            IERC1155(_contractAddress).safeTransferFrom(
                address(this),
                ask.asker,
                ask.tokenId,
                _amount,
                ""
            );
        }

        emit CancelAskLog(_contractAddress, _askId, _amount);
    }

    event AcceptAskLog(
        address indexed userAddress,
        address indexed contractAddress,
        uint256 indexed askId,
        uint256 amount
    );

    function acceptAsk(
        address _contractAddress,
        uint256 _askId,
        uint256 _amount
    ) public nonReentrant {
        require(_amount > 0, "Zero amount");

        Ask memory ask = collectionData[_contractAddress].asks[_askId];

        require(block.timestamp <= ask.deadlineTimestamp, "Ask expired");

        uint256 newAmount = ask.amount.sub(_amount, "Not enough available");
        if (newAmount == 0) {
            delete collectionData[_contractAddress].asks[_askId];
        } else {
            collectionData[_contractAddress].asks[_askId].amount = newAmount;
        }

        uint256 totalPrice = _amount.mul(ask.currencyAmountPerUnit);

        uint256 tradeFee = totalPrice.mul(tradeFeeMultiplier) / 10000;
        if (tradeFee > 0) {
            ask.currency.safeTransferFrom(msg.sender, owner(), tradeFee);
        }

        uint256 royaltyFee = totalPrice.mul(
            collectionData[_contractAddress].royalty[ask.tokenId].multiplier
        ) / 10000;
        if (royaltyFee > 0) {
            ask.currency.safeTransferFrom(
                msg.sender,
                collectionData[_contractAddress].royalty[ask.tokenId].to,
                royaltyFee
            );
        }

        ask.currency.safeTransferFrom(
            msg.sender,
            ask.asker,
            totalPrice - tradeFee - royaltyFee
        );

        if (
            collectionData[_contractAddress].collectionType ==
            CollectionType.ERC721
        ) {
            IERC721(_contractAddress).safeTransferFrom(
                address(this),
                msg.sender,
                ask.tokenId
            );
        } else {
            IERC1155(_contractAddress).safeTransferFrom(
                address(this),
                msg.sender,
                ask.tokenId,
                _amount,
                ""
            );
        }

        emit AcceptAskLog(msg.sender, _contractAddress, _askId, _amount);
    }

    event CreateBidLog(
        address indexed userAddress,
        address indexed contractAddress,
        uint256 indexed bidId,
        uint256 tokenId,
        uint256 amount,
        address currency,
        uint256 currencyAmountPerUnit,
        uint256 deadlineTimestamp
    );

    function createBid(
        address _contractAddress,
        uint256 _tokenId,
        uint256 _amount,
        IERC20 _currency,
        uint256 _currencyAmountPerUnit,
        uint256 _deadlineTimestamp
    ) public nonReentrant {
        require(_currencyAmountPerUnit > 0, "Zero currency amount per unit");
        require(_deadlineTimestamp > block.timestamp, "Invalid deadline");
        require(
            whitelistedCurrencies[address(_currency)],
            "Currency not whitelisted"
        );

        CollectionType collectionType = collectionData[_contractAddress]
            .collectionType;
        require(
            collectionType != CollectionType.NONE,
            "Contract not whitelisted"
        );

        uint256 amount = 1;
        if (collectionType == CollectionType.ERC1155) {
            require(_amount > 0, "Zero amount");
            amount = _amount;
        }

        uint256 bidId = collectionData[_contractAddress].nextBidId;
        collectionData[_contractAddress].nextBidId = bidId.add(1);

        collectionData[_contractAddress].bids[bidId] = Bid({
            tokenId: _tokenId,
            amount: amount,
            bidder: msg.sender,
            currency: _currency,
            currencyAmountPerUnit: _currencyAmountPerUnit,
            deadlineTimestamp: _deadlineTimestamp
        });

        _currency.safeTransferFrom(
            msg.sender,
            address(this),
            amount.mul(_currencyAmountPerUnit)
        );

        emit CreateBidLog(
            msg.sender,
            _contractAddress,
            bidId,
            _tokenId,
            amount,
            address(_currency),
            _currencyAmountPerUnit,
            _deadlineTimestamp
        );
    }

    event UpdateBidDeadlineLog(
        address indexed contractAddress,
        uint256 indexed bidId,
        uint256 deadlineTimestamp
    );

    function updateBidDeadline(
        address _contractAddress,
        uint256 _bidId,
        uint256 _deadlineTimestamp
    ) public nonReentrant {
        require(_deadlineTimestamp > block.timestamp, "Invalid deadline");
        require(
            msg.sender == collectionData[_contractAddress].bids[_bidId].bidder,
            "Only bidder"
        );

        collectionData[_contractAddress]
            .bids[_bidId]
            .deadlineTimestamp = _deadlineTimestamp;

        emit UpdateBidDeadlineLog(_contractAddress, _bidId, _deadlineTimestamp);
    }

    event CancelBidLog(
        address indexed contractAddress,
        uint256 indexed bidId,
        uint256 amount
    );

    function cancelBid(
        address _contractAddress,
        uint256 _bidId,
        uint256 _amount
    ) public nonReentrant {
        require(_amount > 0, "Zero amount");

        Bid memory bid = collectionData[_contractAddress].bids[_bidId];

        require(msg.sender == bid.bidder, "Only bidder");

        uint256 newAmount = bid.amount.sub(_amount, "Not enough available");
        if (newAmount == 0) {
            delete collectionData[_contractAddress].bids[_bidId];
        } else {
            collectionData[_contractAddress].bids[_bidId].amount = newAmount;
        }

        bid.currency.safeTransfer(
            bid.bidder,
            _amount.mul(bid.currencyAmountPerUnit)
        );

        emit CancelBidLog(_contractAddress, _bidId, _amount);
    }

    event AcceptBidLog(
        address indexed userAddress,
        address indexed contractAddress,
        uint256 indexed bidId,
        uint256 amount
    );

    function acceptBid(
        address _contractAddress,
        uint256 _bidId,
        uint256 _amount
    ) public nonReentrant {
        require(_amount > 0, "Zero amount");

        Bid memory bid = collectionData[_contractAddress].bids[_bidId];

        require(block.timestamp <= bid.deadlineTimestamp, "Bid expired");

        uint256 newAmount = bid.amount.sub(_amount, "Not enough available");
        if (newAmount == 0) {
            delete collectionData[_contractAddress].bids[_bidId];
        } else {
            collectionData[_contractAddress].bids[_bidId].amount = newAmount;
        }

        uint256 totalPrice = _amount.mul(bid.currencyAmountPerUnit);

        uint256 tradeFee = totalPrice.mul(tradeFeeMultiplier) / 10000;
        if (tradeFee > 0) {
            bid.currency.safeTransfer(owner(), tradeFee);
        }

        uint256 royaltyFee = totalPrice.mul(
            collectionData[_contractAddress].royalty[bid.tokenId].multiplier
        ) / 10000;
        if (royaltyFee > 0) {
            bid.currency.safeTransfer(
                collectionData[_contractAddress].royalty[bid.tokenId].to,
                royaltyFee
            );
        }

        bid.currency.safeTransfer(
            msg.sender,
            totalPrice - tradeFee - royaltyFee
        );

        if (
            collectionData[_contractAddress].collectionType ==
            CollectionType.ERC721
        ) {
            IERC721(_contractAddress).safeTransferFrom(
                msg.sender,
                bid.bidder,
                bid.tokenId
            );
        } else {
            IERC1155(_contractAddress).safeTransferFrom(
                msg.sender,
                bid.bidder,
                bid.tokenId,
                _amount,
                ""
            );
        }

        emit AcceptBidLog(msg.sender, _contractAddress, _bidId, _amount);
    }

    function replaceAsk(
        address _contractAddress,
        uint256 _askId,
        uint256 _cancelAmount,
        uint256 _tokenId,
        uint256 _createAmount,
        IERC20 _currency,
        uint256 _currencyAmountPerUnit,
        uint256 _deadlineTimestamp
    ) external {
        cancelAsk(_contractAddress, _askId, _cancelAmount);

        createAsk(
            _contractAddress,
            _tokenId,
            _createAmount,
            _currency,
            _currencyAmountPerUnit,
            _deadlineTimestamp
        );
    }

    function replaceBid(
        address _contractAddress,
        uint256 _bidId,
        uint256 _cancelAmount,
        uint256 _tokenId,
        uint256 _createAmount,
        IERC20 _currency,
        uint256 _currencyAmountPerUnit,
        uint256 _deadlineTimestamp
    ) external {
        cancelBid(_contractAddress, _bidId, _cancelAmount);

        createBid(
            _contractAddress,
            _tokenId,
            _createAmount,
            _currency,
            _currencyAmountPerUnit,
            _deadlineTimestamp
        );
    }

    function cancelAskAndAcceptBid(
        address _contractAddress,
        uint256 _askId,
        uint256 _cancelAmount,
        uint256 _bidId,
        uint256 _acceptAmount
    ) external {
        cancelAsk(_contractAddress, _askId, _cancelAmount);

        acceptBid(_contractAddress, _bidId, _acceptAmount);
    }

    function cancelBidAndAcceptAsk(
        address _contractAddress,
        uint256 _bidId,
        uint256 _cancelAmount,
        uint256 _askId,
        uint256 _acceptAmount
    ) external {
        cancelBid(_contractAddress, _bidId, _cancelAmount);

        acceptAsk(_contractAddress, _askId, _acceptAmount);
    }

    function getAsk(address _contractAddress, uint256 _askId)
        external
        view
        returns (Ask memory)
    {
        return collectionData[_contractAddress].asks[_askId];
    }

    function getBid(address _contractAddress, uint256 _bidId)
        external
        view
        returns (Bid memory)
    {
        return collectionData[_contractAddress].bids[_bidId];
    }

    function getRoyalty(address _contractAddress, uint256 _tokenId)
        external
        view
        returns (RoyaltyInfo memory)
    {
        return collectionData[_contractAddress].royalty[_tokenId];
    }

    /**
     ** Owner
     */

    function renounceOwnership() public override onlyOwner {
        tradeFeeMultiplier = 0;

        super.renounceOwnership();
    }

    function setTradeFeeMultiplier(uint256 _newMultiplier) external onlyOwner {
        require(_newMultiplier <= 2500, "Maximum fee is 25%");

        tradeFeeMultiplier = _newMultiplier;
    }

    function whitelistContract(
        address _contractAddress,
        CollectionType _collectionType
    ) external onlyOwner {
        require(
            _collectionType != CollectionType.NONE,
            "Invalid contract type"
        );

        collectionData[_contractAddress].collectionType = _collectionType;
    }

    function setRoyaltyMultiplier(
        address _contractAddress,
        uint256 _tokenId,
        address _to,
        uint256 _multiplier
    ) external onlyOwner {
        if (_to == address(0)) {
            delete collectionData[_contractAddress].royalty[_tokenId];
        } else {
            require(_multiplier > 0, "Invalid royalty");
            require(_multiplier <= 2500, "Maximum royalty is 25%");

            collectionData[_contractAddress].royalty[_tokenId] = RoyaltyInfo({
                to: _to,
                multiplier: _multiplier
            });
        }
    }

    function whitelistCurrency(address _currencyAddress) external onlyOwner {
        whitelistedCurrencies[_currencyAddress] = true;
    }

    function blacklistCurrency(address _currencyAddress) external onlyOwner {
        whitelistedCurrencies[_currencyAddress] = false;
    }
}
