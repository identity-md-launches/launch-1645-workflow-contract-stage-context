// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Deploy} from "../script/Deploy.s.sol";
import {MockSeats} from "./mocks/MockSeats.sol";

contract DeployTest is Test {
    function test_deployAllWiresContractsInManifestOrder() public {
        MockSeats seats = new MockSeats();
        Deploy script = new Deploy();
        Deploy.Deployed memory d = script.deployAll(address(seats));

        // The token mints to its deployer, here the script, as it will to the factory.
        assertEq(d.token.balanceOf(address(script)), 10 ** 27);
        assertEq(address(d.nft.VIMD()), address(d.token));
        assertEq(address(d.nft.SEATS()), address(seats));
        assertEq(address(d.nft.ART_A()), address(d.artA));
        assertEq(address(d.nft.ART_B()), address(d.artB));
        assertEq(address(d.nft.ART_C()), address(d.artC));
        assertEq(d.nft.VOTE_END(), block.timestamp + 7 days);
        assertEq(script.SEATS(), 0x0000eC93127BAA929E58E97dd0095A2BFb38ec1D);
    }
}
