// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {FinalistArtA} from "../src/FinalistArtA.sol";
import {FinalistArtB} from "../src/FinalistArtB.sol";
import {FinalistArtC} from "../src/FinalistArtC.sol";

/// @notice The expected strings below are the exact bytes of art/finalist-{a,b,c}/logomark.svg.
///         Changing a logomark file means changing both the art contract and this test.
contract FinalistArtTest is Test {
    string internal constant SVG_A =
        "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64' width='64' height='64'><title>Keystone</title><path d='M32 4 56 18v28L32 60 8 46V18z' fill='#1F2A6B'/><path d='M32 14 46 22v20L32 50 18 42V22z' fill='#F26B4E'/><path d='M22 30h20v6H22z' fill='#FFFFFF'/><path d='M29 20h6v24h-6z' fill='#FFFFFF'/></svg>";
    string internal constant SVG_B =
        "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64' width='64' height='64'><title>Orbit</title><circle cx='32' cy='32' r='28' fill='#0B3D3A'/><circle cx='32' cy='32' r='19' fill='none' stroke='#2EC4B6' stroke-width='4'/><circle cx='32' cy='32' r='8' fill='#F4F1DE'/><circle cx='51' cy='32' r='5' fill='#F4F1DE'/></svg>";
    string internal constant SVG_C =
        "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64' width='64' height='64'><title>Lattice</title><rect x='4' y='4' width='56' height='56' rx='12' fill='#22223B'/><rect x='12' y='12' width='12' height='12' rx='2' fill='#F2A900'/><rect x='40' y='12' width='12' height='12' rx='2' fill='#F2A900'/><rect x='26' y='26' width='12' height='12' rx='2' fill='#FFFFFF'/><rect x='12' y='40' width='12' height='12' rx='2' fill='#F2A900'/><rect x='40' y='40' width='12' height='12' rx='2' fill='#F2A900'/></svg>";

    FinalistArtA internal a;
    FinalistArtB internal b;
    FinalistArtC internal c;

    function setUp() public {
        a = new FinalistArtA();
        b = new FinalistArtB();
        c = new FinalistArtC();
    }

    function test_returnsExactSvg() public view {
        assertEq(a.logomark(), SVG_A);
        assertEq(b.logomark(), SVG_B);
        assertEq(c.logomark(), SVG_C);
    }

    function test_letters() public view {
        assertEq(a.finalist(), "A");
        assertEq(b.finalist(), "B");
        assertEq(c.finalist(), "C");
    }

    function test_svgsAreDistinctWellFormedAndSmall() public view {
        string[3] memory svgs = [a.logomark(), b.logomark(), c.logomark()];
        for (uint256 i; i < 3; ++i) {
            bytes memory s = bytes(svgs[i]);
            assertLt(s.length, 4096, "logomark must be under 4 KB");
            assertTrue(_startsWith(s, "<svg "), "must start with <svg");
            assertTrue(_endsWith(s, "</svg>"), "must end with </svg>");
            assertFalse(_contains(s, "<image"), "no raster");
            assertFalse(_contains(s, "@font-face"), "no external fonts");
            assertFalse(_contains(s, "<text"), "paths and shapes only");
        }
        assertTrue(keccak256(bytes(svgs[0])) != keccak256(bytes(svgs[1])));
        assertTrue(keccak256(bytes(svgs[1])) != keccak256(bytes(svgs[2])));
        assertTrue(keccak256(bytes(svgs[0])) != keccak256(bytes(svgs[2])));
    }

    function _startsWith(bytes memory s, string memory p) internal pure returns (bool) {
        bytes memory pb = bytes(p);
        if (s.length < pb.length) return false;
        for (uint256 i; i < pb.length; ++i) {
            if (s[i] != pb[i]) return false;
        }
        return true;
    }

    function _endsWith(bytes memory s, string memory p) internal pure returns (bool) {
        bytes memory pb = bytes(p);
        if (s.length < pb.length) return false;
        uint256 off = s.length - pb.length;
        for (uint256 i; i < pb.length; ++i) {
            if (s[off + i] != pb[i]) return false;
        }
        return true;
    }

    function _contains(bytes memory s, string memory p) internal pure returns (bool) {
        bytes memory pb = bytes(p);
        if (s.length < pb.length) return false;
        for (uint256 i; i + pb.length <= s.length; ++i) {
            bool match_ = true;
            for (uint256 j; j < pb.length; ++j) {
                if (s[i + j] != pb[j]) {
                    match_ = false;
                    break;
                }
            }
            if (match_) return true;
        }
        return false;
    }
}
