// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title VisualIdentity.md launch token (VIMD)
/// @notice Fixed-supply ERC-20: 1,000,000,000 tokens at 18 decimals, minted once to the deployer
///         (the IMD ProjectFactory), which splits the supply at launch. No owner, mint, pause,
///         blocklist, fee or upgrade paths exist.
contract LaunchToken is ERC20 {
    /// @notice The whole supply, in minor units: 10^27.
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 ether;

    constructor() ERC20("VisualIdentity.md", "VIMD") {
        _mint(msg.sender, TOTAL_SUPPLY);
    }
}
