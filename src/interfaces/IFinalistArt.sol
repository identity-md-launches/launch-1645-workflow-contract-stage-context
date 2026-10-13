// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.26;

/// @title On-chain logomark of one VisualIdentity.md finalist
interface IFinalistArt {
    /// @notice The finalist's logomark SVG, byte for byte as published in its brand-guide folder.
    function logomark() external pure returns (string memory);

    /// @notice The finalist letter: "A", "B" or "C".
    function finalist() external pure returns (string memory);
}
