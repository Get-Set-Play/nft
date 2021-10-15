// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

interface INFT {
    function create(
        uint256[] calldata _maximumSupplies,
        string[] calldata _tokenURIs
    ) external;

    function mint(
        address _toAddress,
        uint256 _id,
        uint256 _amount
    ) external;

    function mintBatch(
        address _toAddress,
        uint256[] calldata _ids,
        uint256[] calldata _amounts
    ) external;

    function burn(
        address account,
        uint256 id,
        uint256 value
    ) external;

    function burnBatch(
        address account,
        uint256[] memory ids,
        uint256[] memory values
    ) external;
}
