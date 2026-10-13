// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {LaunchToken} from "../src/LaunchToken.sol";
import {FinalistArtA} from "../src/FinalistArtA.sol";
import {FinalistArtB} from "../src/FinalistArtB.sol";
import {FinalistArtC} from "../src/FinalistArtC.sol";
import {BrandGenesisNFT} from "../src/BrandGenesisNFT.sol";

/// @title Local / fork deployment of the whole project, for review and reproduction only.
/// @notice The production launch is performed by IMD's ProjectFactory from launch.json, not by this
///         script. It mirrors the manifest's dependency order: token, FinalistArtA, FinalistArtB,
///         FinalistArtC, then BrandGenesisNFT($token, SEATS, $contract:FinalistArtA/B/C).
contract Deploy is Script {
    /// @notice The identity.md seat collection on Ethereum mainnet (from the approved workflow).
    address public constant SEATS = 0x0000eC93127BAA929E58E97dd0095A2BFb38ec1D;

    struct Deployed {
        LaunchToken token;
        FinalistArtA artA;
        FinalistArtB artB;
        FinalistArtC artC;
        BrandGenesisNFT nft;
    }

    /// @notice Deploys everything with the token minted to the caller, as the factory would receive it.
    /// @param seats The seat collection the NFT reads `ownerOf` from.
    function deployAll(address seats) public returns (Deployed memory d) {
        d.token = new LaunchToken();
        d.artA = new FinalistArtA();
        d.artB = new FinalistArtB();
        d.artC = new FinalistArtC();
        d.nft = new BrandGenesisNFT(address(d.token), seats, address(d.artA), address(d.artB), address(d.artC));
    }

    /// @notice Broadcast entry point for a fork or testnet rehearsal. Not used by the launch.
    function run() external returns (Deployed memory d) {
        vm.startBroadcast();
        d = deployAll(SEATS);
        vm.stopBroadcast();
    }
}
