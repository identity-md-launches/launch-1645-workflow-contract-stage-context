// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/// @notice Test stand-in for the identity.md seat collection. Anyone can mint any id.
contract MockSeats is ERC721 {
    constructor() ERC721("Mock Seats", "SEAT") {}

    function mint(address to, uint256 id) external {
        _mint(to, id);
    }
}
