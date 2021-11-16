// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721Burnable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./helpers/ContextMixin.sol";
import "./helpers/NativeMetaTransaction.sol";

contract SoldiersSociety is
    ERC721Burnable,
    ContextMixin,
    NativeMetaTransaction,
    ReentrancyGuard,
    Ownable
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant pricePerSoldier = 500 ether;
    uint256 public constant maximumSupply = 3333;
    uint256 public constant reservedSupply = 111;
    uint256 public unmintedSupply;

    IERC20 public immutable xedContract;
    address public immutable paymentSplitterContract;
    bool public saleActive;

    constructor(
        string memory _name,
        string memory _symbol,
        IERC20 _xedContract,
        address _paymentSplitterContract
    ) ERC721(_name, _symbol) {
        xedContract = _xedContract;
        paymentSplitterContract = _paymentSplitterContract;

        _initializeEIP712(_name);

        // Mint the reserved supply
        unmintedSupply = maximumSupply - reservedSupply;
        for (uint256 i = 0; i < reservedSupply; i++) {
            _safeMint(msg.sender, i);
        }
    }

    /**
     ** Users
     */

    function mint(uint256 _amount) external nonReentrant {
        require(saleActive, "Sale is not active");

        require(_amount > 0, "Nothing to mint");
        require(_amount <= 100, "Too many to mint");

        uint256 previousUnmintedSupply = unmintedSupply;
        unmintedSupply = previousUnmintedSupply.sub(
            _amount,
            "Not enough available"
        );

        xedContract.safeTransferFrom(
            msg.sender,
            address(this),
            _amount.mul(pricePerSoldier)
        );

        for (uint256 i = 0; i < _amount; i++) {
            uint256 tokenId = maximumSupply - previousUnmintedSupply + i;
            _safeMint(msg.sender, tokenId);
        }
    }

    function withdraw() external {
        uint256 available = xedContract.balanceOf(address(this));
        require(available > 0, "Nothing to withdraw");

        // Until the end of the tournament (2021-12-05 23:59:59), send the funds to the payment splitter contract.
        if (block.timestamp < 1638748800) {
            xedContract.safeTransfer(paymentSplitterContract, available);
        } else {
            xedContract.safeTransfer(owner(), available);
        }
    }

    /**
     ** Owner
     */

    function startSale() external onlyOwner {
        require(!saleActive, "Sale is already active");
        saleActive = true;
    }

    /**
     ** OpenSea and Standards
     */

    function tokenURI(uint256 _tokenId)
        public
        pure
        override
        returns (string memory)
    {
        return
            string(
                abi.encodePacked(
                    "ipfs://QmbBEpAvdKJhwtZNEZGf1K4S1wxL9CLPBMdT44Y4vesrnq/",
                    Strings.toString(_tokenId),
                    ".json"
                )
            );
    }

    function isApprovedForAll(address _owner, address _operator)
        public
        view
        override
        returns (bool)
    {
        if (_operator == address(0x58807baD0B376efc12F5AD86aAc70E78ed67deaE)) {
            return true;
        }

        return super.isApprovedForAll(_owner, _operator);
    }

    function _msgSender()
        internal
        view
        override
        returns (address payable sender)
    {
        return ContextMixin.msgSender();
    }
}
