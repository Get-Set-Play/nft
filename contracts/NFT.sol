// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155Burnable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./INFT.sol";
import "./helpers/ContextMixin.sol";
import "./helpers/NativeMetaTransaction.sol";

contract NFT is
    ERC1155Burnable,
    ContextMixin,
    NativeMetaTransaction,
    AccessControl,
    ReentrancyGuard,
    Ownable
{
    using SafeMath for uint256;

    bytes32 public constant MINTER = keccak256("MINTER");

    uint256 public nextTokenId = 0;

    mapping(uint256 => uint256) public mintableTokens;
    mapping(uint256 => string) private tokenURIs;

    string public name;
    string public symbol;

    event CreateNFTLog(uint256 indexed id, uint256 maximumSupply, string uri);

    constructor(string memory _name, string memory _symbol) ERC1155("") {
        name = _name;
        symbol = _symbol;

        _initializeEIP712(_name);

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MINTER, msg.sender);
    }

    /**
     ** Minters
     */

    function create(
        uint256[] calldata _maximumSupplies,
        string[] calldata _tokenURIs
    ) external {
        require(hasRole(MINTER, msg.sender), "Only minter");
        require(_maximumSupplies.length > 0, "No tokens to create");
        require(
            _maximumSupplies.length == _tokenURIs.length,
            "Lengths do not match"
        );

        uint256 nextId = nextTokenId;
        for (uint256 i = 0; i < _tokenURIs.length; i++) {
            uint256 id = nextId.add(i);
            mintableTokens[id] = _maximumSupplies[i];
            tokenURIs[id] = _tokenURIs[i];

            emit CreateNFTLog(id, _maximumSupplies[i], _tokenURIs[i]);
        }
        nextTokenId = nextId.add(_tokenURIs.length);
    }

    function mint(
        address _account,
        uint256 _id,
        uint256 _amount
    ) external nonReentrant {
        require(hasRole(MINTER, msg.sender), "Only minter");

        mintableTokens[_id] = mintableTokens[_id].sub(
            _amount,
            "Not enough tokens available to mint"
        );

        _mint(_account, _id, _amount, "");
    }

    function mintBatch(
        address _account,
        uint256[] calldata _ids,
        uint256[] calldata _amounts
    ) external nonReentrant {
        require(hasRole(MINTER, msg.sender), "Only minter");

        for (uint256 i = 0; i < _ids.length; i++) {
            mintableTokens[_ids[i]] = mintableTokens[_ids[i]].sub(
                _amounts[i],
                "Not enough tokens available to mint"
            );
        }

        _mintBatch(_account, _ids, _amounts, "");
    }

    /**
     ** OpenSea and Standards
     */

    function uri(uint256 _tokenId)
        external
        view
        override
        returns (string memory)
    {
        return string(abi.encodePacked("ipfs://", tokenURIs[_tokenId]));
    }

    function isApprovedForAll(address _owner, address _operator)
        public
        view
        override
        returns (bool)
    {
        if (_operator == address(0x207Fa8Df3a17D96Ca7EA4f2893fcdCb78a304101)) {
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
