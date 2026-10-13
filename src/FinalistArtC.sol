// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.26;

import {IFinalistArt} from "./interfaces/IFinalistArt.sol";

/// @title Finalist C logomark, "Lattice"
/// @notice Returns art/finalist-c/logomark.svg exactly. Immutable, no state, no owner.
contract FinalistArtC is IFinalistArt {
    string private constant SVG =
        "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64' width='64' height='64'><title>Lattice</title><rect x='4' y='4' width='56' height='56' rx='12' fill='#22223B'/><rect x='12' y='12' width='12' height='12' rx='2' fill='#F2A900'/><rect x='40' y='12' width='12' height='12' rx='2' fill='#F2A900'/><rect x='26' y='26' width='12' height='12' rx='2' fill='#FFFFFF'/><rect x='12' y='40' width='12' height='12' rx='2' fill='#F2A900'/><rect x='40' y='40' width='12' height='12' rx='2' fill='#F2A900'/></svg>";

    /// @inheritdoc IFinalistArt
    function logomark() external pure returns (string memory) {
        return SVG;
    }

    /// @inheritdoc IFinalistArt
    function finalist() external pure returns (string memory) {
        return "C";
    }
}
