// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.26;

import {IFinalistArt} from "./interfaces/IFinalistArt.sol";

/// @title Finalist A logomark, "Keystone"
/// @notice Returns art/finalist-a/logomark.svg exactly. Immutable, no state, no owner.
contract FinalistArtA is IFinalistArt {
    string private constant SVG =
        "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64' width='64' height='64'><title>Keystone</title><path d='M32 4 56 18v28L32 60 8 46V18z' fill='#1F2A6B'/><path d='M32 14 46 22v20L32 50 18 42V22z' fill='#F26B4E'/><path d='M22 30h20v6H22z' fill='#FFFFFF'/><path d='M29 20h6v24h-6z' fill='#FFFFFF'/></svg>";

    /// @inheritdoc IFinalistArt
    function logomark() external pure returns (string memory) {
        return SVG;
    }

    /// @inheritdoc IFinalistArt
    function finalist() external pure returns (string memory) {
        return "A";
    }
}
