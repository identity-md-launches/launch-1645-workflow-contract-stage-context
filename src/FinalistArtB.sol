// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.26;

import {IFinalistArt} from "./interfaces/IFinalistArt.sol";

/// @title Finalist B logomark, "Orbit"
/// @notice Returns art/finalist-b/logomark.svg exactly. Immutable, no state, no owner.
contract FinalistArtB is IFinalistArt {
    string private constant SVG =
        "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64' width='64' height='64'><title>Orbit</title><circle cx='32' cy='32' r='28' fill='#0B3D3A'/><circle cx='32' cy='32' r='19' fill='none' stroke='#2EC4B6' stroke-width='4'/><circle cx='32' cy='32' r='8' fill='#F4F1DE'/><circle cx='51' cy='32' r='5' fill='#F4F1DE'/></svg>";

    /// @inheritdoc IFinalistArt
    function logomark() external pure returns (string memory) {
        return SVG;
    }

    /// @inheritdoc IFinalistArt
    function finalist() external pure returns (string memory) {
        return "B";
    }
}
