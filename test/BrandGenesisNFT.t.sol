// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {LaunchToken} from "../src/LaunchToken.sol";
import {FinalistArtA} from "../src/FinalistArtA.sol";
import {FinalistArtB} from "../src/FinalistArtB.sol";
import {FinalistArtC} from "../src/FinalistArtC.sol";
import {BrandGenesisNFT} from "../src/BrandGenesisNFT.sol";
import {IFinalistArt} from "../src/interfaces/IFinalistArt.sol";
import {MockSeats} from "./mocks/MockSeats.sol";
import {Base64Decoder} from "./utils/Base64Decoder.sol";

/// @notice A seat collection whose `ownerOf` tries to re-enter `vote`. Because `ownerOf` is reached
///         through a STATICCALL, any state change inside it reverts, so the re-entry cannot succeed.
contract ReentrantSeats {
    BrandGenesisNFT public nft;

    function setNft(BrandGenesisNFT nft_) external {
        nft = nft_;
    }

    function ownerOf(uint256) external view returns (address) {
        // A view function cannot write; the compiler forbids calling a non-view function here, so the
        // re-entry is attempted through a raw call, which inherits the STATICCALL context and reverts.
        (bool ok,) = address(nft).staticcall(abi.encodeWithSelector(BrandGenesisNFT.vote.selector, 1, 0));
        require(ok, "reentrant vote failed");
        return msg.sender;
    }
}

contract BrandGenesisNFTTest is Test {
    using Base64Decoder for string;

    uint256 internal constant BURN = 50_000e18;
    address internal constant DEAD = 0x000000000000000000000000000000000000dEaD;

    LaunchToken internal vimd;
    MockSeats internal seats;
    FinalistArtA internal artA;
    FinalistArtB internal artB;
    FinalistArtC internal artC;
    BrandGenesisNFT internal nft;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    uint256 internal deployedAt;

    event Voted(uint256 indexed seatId, uint8 indexed finalist, address indexed voter, uint256 tokenId);
    event BurnMinted(address indexed minter, uint8 indexed finalist, uint256 tokenId, uint256 vimdBurned);
    event Burned(uint256 indexed tokenId, address indexed by);

    function setUp() public {
        vm.warp(1_800_000_000);
        deployedAt = block.timestamp;
        vimd = new LaunchToken();
        seats = new MockSeats();
        artA = new FinalistArtA();
        artB = new FinalistArtB();
        artC = new FinalistArtC();
        nft = new BrandGenesisNFT(address(vimd), address(seats), address(artA), address(artB), address(artC));

        seats.mint(alice, 0);
        seats.mint(alice, 1);
        seats.mint(bob, 2);
        seats.mint(carol, 1999);

        vimd.transfer(alice, 1_000_000e18);
        vimd.transfer(bob, 1_000_000e18);
    }

    // ───────────────────────────── deployment ─────────────────────────────

    function test_deploymentConstants() public view {
        assertEq(nft.name(), "Visual Identity Genesis");
        assertEq(nft.symbol(), "VIMDG");
        assertEq(nft.EDITION(), 1);
        assertEq(nft.VOTE_END(), deployedAt + 7 days);
        assertEq(nft.BURN_AMOUNT(), BURN);
        assertEq(nft.DEAD(), DEAD);
        assertEq(address(nft.VIMD()), address(vimd));
        assertEq(address(nft.SEATS()), address(seats));
        assertEq(address(nft.ART_A()), address(artA));
        assertEq(address(nft.ART_B()), address(artB));
        assertEq(address(nft.ART_C()), address(artC));
        assertEq(address(nft.artOf(0)), address(artA));
        assertEq(address(nft.artOf(1)), address(artB));
        assertEq(address(nft.artOf(2)), address(artC));
        assertEq(nft.totalMinted(), 0);
        assertEq(nft.totalBurned(), 0);
        assertEq(nft.totalSupply(), 0);
        assertTrue(nft.votingOpen());
    }

    function test_constructorRejectsZeroAddresses() public {
        vm.expectRevert(BrandGenesisNFT.ZeroAddress.selector);
        new BrandGenesisNFT(address(0), address(seats), address(artA), address(artB), address(artC));
        vm.expectRevert(BrandGenesisNFT.ZeroAddress.selector);
        new BrandGenesisNFT(address(vimd), address(0), address(artA), address(artB), address(artC));
        vm.expectRevert(BrandGenesisNFT.ZeroAddress.selector);
        new BrandGenesisNFT(address(vimd), address(seats), address(0), address(artB), address(artC));
        vm.expectRevert(BrandGenesisNFT.ZeroAddress.selector);
        new BrandGenesisNFT(address(vimd), address(seats), address(artA), address(0), address(artC));
        vm.expectRevert(BrandGenesisNFT.ZeroAddress.selector);
        new BrandGenesisNFT(address(vimd), address(seats), address(artA), address(artB), address(0));
    }

    function test_constructorCallsNoOtherContract() public {
        // Addresses with no code at all: the constructor must still succeed, as it does on the
        // launch's empty check chain.
        address a = address(0x1111);
        address b = address(0x2222);
        BrandGenesisNFT fresh = new BrandGenesisNFT(a, b, a, b, a);
        assertEq(fresh.VOTE_END(), block.timestamp + 7 days);
    }

    function test_noOwnerOrAdminSurface() public {
        string[6] memory sigs = [
            "owner()", "pause()", "transferOwnership(address)", "withdraw()", "setSeats(address)", "upgradeTo(address)"
        ];
        for (uint256 i; i < sigs.length; ++i) {
            (bool ok,) = address(nft).call(abi.encodeWithSignature(sigs[i], alice));
            assertFalse(ok, sigs[i]);
        }
    }

    // ───────────────────────────── vote ─────────────────────────────

    function test_seatOwnerVotes() public {
        vm.expectEmit(true, true, true, true);
        emit Voted(0, 1, alice, 1);
        vm.prank(alice);
        nft.vote(0, 1);

        assertEq(nft.ownerOf(1), alice);
        assertEq(nft.balanceOf(alice), 1);
        assertEq(nft.votes(1), 1);
        assertEq(nft.votes(0), 0);
        assertEq(nft.votes(2), 0);
        assertEq(nft.totalVotes(), 1);
        assertTrue(nft.seatVoted(0));
        assertFalse(nft.seatVoted(1));
        assertEq(nft.finalistOf(1), 1);
        assertTrue(nft.isVoteToken(1));
        assertEq(nft.seatOf(1), 0);
        assertEq(nft.totalMinted(), 1);
        assertEq(nft.totalVoteMints(), 1);
        assertEq(nft.leader(), 1);
    }

    function test_onlySeatOwnerVotes() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(BrandGenesisNFT.NotSeatOwner.selector, 0, bob));
        nft.vote(0, 0);

        // An approved operator of the seat is not its owner either.
        vm.prank(alice);
        seats.setApprovalForAll(bob, true);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(BrandGenesisNFT.NotSeatOwner.selector, 0, bob));
        nft.vote(0, 0);

        assertEq(nft.totalVotes(), 0);
    }

    function test_unmintedSeatCannotVote() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 7));
        nft.vote(7, 0);
    }

    function test_seatOutOfRangeReverts() public {
        seats.mint(alice, 2000);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BrandGenesisNFT.InvalidSeat.selector, 2000));
        nft.vote(2000, 0);
    }

    function test_oneVotePerSeatEver() public {
        vm.prank(alice);
        nft.vote(0, 0);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BrandGenesisNFT.SeatAlreadyVoted.selector, 0));
        nft.vote(0, 2);

        // Same seat, same owner, other finalist: still refused.
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BrandGenesisNFT.SeatAlreadyVoted.selector, 0));
        nft.vote(0, 0);

        // Alice's other seat may still vote.
        vm.prank(alice);
        nft.vote(1, 2);
        assertEq(nft.totalVotes(), 2);
    }

    function test_oneVotePerSeatAfterTransfer() public {
        vm.prank(alice);
        nft.vote(0, 0);

        vm.prank(alice);
        seats.transferFrom(alice, bob, 0);
        assertEq(seats.ownerOf(0), bob);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(BrandGenesisNFT.SeatAlreadyVoted.selector, 0));
        nft.vote(0, 1);
        assertEq(nft.votes(1), 0);

        // Burning the vote NFT does not free the seat either.
        vm.prank(alice);
        nft.burn(1);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(BrandGenesisNFT.SeatAlreadyVoted.selector, 0));
        nft.vote(0, 1);
    }

    function test_transferredSeatVotesWithNewOwnerIfUnused() public {
        vm.prank(alice);
        seats.transferFrom(alice, bob, 0);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BrandGenesisNFT.NotSeatOwner.selector, 0, alice));
        nft.vote(0, 0);
        vm.prank(bob);
        nft.vote(0, 0);
        assertEq(nft.ownerOf(1), bob);
    }

    function test_noVoteAtOrAfterVoteEnd() public {
        vm.warp(nft.VOTE_END() - 1);
        vm.prank(alice);
        nft.vote(0, 0);

        vm.warp(nft.VOTE_END());
        assertFalse(nft.votingOpen());
        vm.prank(alice);
        vm.expectRevert(BrandGenesisNFT.VotingClosed.selector);
        nft.vote(1, 0);

        vm.warp(nft.VOTE_END() + 365 days);
        vm.prank(alice);
        vm.expectRevert(BrandGenesisNFT.VotingClosed.selector);
        nft.vote(1, 0);
        assertEq(nft.totalVotes(), 1);
    }

    function test_voteInvalidFinalistReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BrandGenesisNFT.InvalidFinalist.selector, 3));
        nft.vote(0, 3);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BrandGenesisNFT.InvalidFinalist.selector, 255));
        nft.vote(0, 255);
        assertFalse(nft.seatVoted(0));
    }

    function testFuzz_voteInvalidFinalistReverts(uint8 finalist) public {
        finalist = uint8(bound(finalist, 3, 255));
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BrandGenesisNFT.InvalidFinalist.selector, finalist));
        nft.vote(0, finalist);
    }

    function testFuzz_voteSeatOutOfRangeReverts(uint256 seatId) public {
        seatId = bound(seatId, 2000, type(uint256).max);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BrandGenesisNFT.InvalidSeat.selector, seatId));
        nft.vote(seatId, 0);
    }

    function testFuzz_anySeatInRangeVotesOnce(uint256 seatId, uint8 finalist) public {
        seatId = bound(seatId, 3, 1998);
        finalist = uint8(bound(finalist, 0, 2));
        seats.mint(carol, seatId);
        vm.prank(carol);
        nft.vote(seatId, finalist);
        assertEq(nft.votes(finalist), 1);
        assertEq(nft.seatOf(1), seatId);
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(BrandGenesisNFT.SeatAlreadyVoted.selector, seatId));
        nft.vote(seatId, finalist);
    }

    function test_voteCapIsTwoThousandSeats() public {
        // Seats 0, 1, 2 and 1999 already exist; mint the rest to carol and vote with all 2,000.
        for (uint256 id = 3; id < 1999; ++id) {
            seats.mint(carol, id);
        }
        vm.prank(alice);
        nft.vote(0, 0);
        vm.prank(alice);
        nft.vote(1, 0);
        vm.prank(bob);
        nft.vote(2, 1);
        vm.startPrank(carol);
        for (uint256 id = 3; id < 2000; ++id) {
            nft.vote(id, uint8(id % 3));
        }
        vm.stopPrank();

        assertEq(nft.totalVoteMints(), 2000);
        assertEq(nft.totalMinted(), 2000);
        assertEq(nft.totalVotes(), 2000);
        assertEq(nft.ownerOf(2000), carol);

        // Every seat id has voted; no id outside the range can.
        seats.mint(carol, 2000);
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(BrandGenesisNFT.InvalidSeat.selector, 2000));
        nft.vote(2000, 0);

        // Burn mints still work and continue the shared id sequence.
        vm.startPrank(alice);
        vimd.approve(address(nft), BURN);
        nft.mint(2);
        vm.stopPrank();
        assertEq(nft.ownerOf(2001), alice);
    }

    function test_reentrantSeatCollectionCannotVoteTwice() public {
        ReentrantSeats evil = new ReentrantSeats();
        BrandGenesisNFT target =
            new BrandGenesisNFT(address(vimd), address(evil), address(artA), address(artB), address(artC));
        evil.setNft(target);
        vm.prank(alice);
        vm.expectRevert("reentrant vote failed");
        target.vote(1, 0);
        assertEq(target.totalMinted(), 0);
        assertEq(target.totalVotes(), 0);
    }

    // ───────────────────────────── burn mint ─────────────────────────────

    function test_burnMintSendsExactlyFiftyThousandToDead() public {
        uint256 aliceBefore = vimd.balanceOf(alice);
        uint256 deadBefore = vimd.balanceOf(DEAD);
        uint256 supplyBefore = vimd.totalSupply();

        vm.startPrank(alice);
        vimd.approve(address(nft), BURN);
        vm.expectEmit(true, true, true, true);
        emit BurnMinted(alice, 2, 1, BURN);
        nft.mint(2);
        vm.stopPrank();

        assertEq(vimd.balanceOf(alice), aliceBefore - BURN);
        assertEq(vimd.balanceOf(DEAD), deadBefore + BURN);
        assertEq(vimd.balanceOf(address(nft)), 0, "the NFT contract never holds VIMD");
        assertEq(vimd.totalSupply(), supplyBefore, "VIMD supply unchanged; burned tokens sit at dEaD");
        assertEq(nft.ownerOf(1), alice);
        assertEq(nft.finalistOf(1), 2);
        assertFalse(nft.isVoteToken(1));
        assertEq(nft.totalBurnMints(), 1);
        assertEq(nft.totalMinted(), 1);
    }

    function test_burnMintNeverCountsAsVote() public {
        vm.startPrank(alice);
        vimd.approve(address(nft), BURN * 3);
        nft.mint(0);
        nft.mint(1);
        nft.mint(2);
        vm.stopPrank();

        assertEq(nft.votes(0), 0);
        assertEq(nft.votes(1), 0);
        assertEq(nft.votes(2), 0);
        assertEq(nft.totalVotes(), 0);
        vm.expectRevert(BrandGenesisNFT.NoVotes.selector);
        nft.leader();
        assertFalse(nft.seatVoted(0));
        assertEq(nft.totalVoteMints(), 0);
    }

    function test_burnMintDoesNotChangeExistingVotes() public {
        vm.prank(alice);
        nft.vote(0, 0);
        vm.prank(bob);
        nft.vote(2, 1);
        vm.startPrank(alice);
        vimd.approve(address(nft), BURN * 2);
        nft.mint(2);
        nft.mint(2);
        vm.stopPrank();
        assertEq(nft.votes(0), 1);
        assertEq(nft.votes(1), 1);
        assertEq(nft.votes(2), 0);
        assertEq(nft.leader(), 0);
    }

    function test_burnMintWorksAfterVoteEnd() public {
        vm.warp(nft.VOTE_END() + 30 days);
        vm.startPrank(alice);
        vimd.approve(address(nft), BURN);
        nft.mint(0);
        vm.stopPrank();
        assertEq(nft.ownerOf(1), alice);
    }

    function test_burnMintWithoutApprovalReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(nft), 0, BURN));
        nft.mint(0);
        assertEq(nft.totalMinted(), 0);
    }

    function test_burnMintWithShortApprovalOrBalanceReverts() public {
        vm.startPrank(alice);
        vimd.approve(address(nft), BURN - 1);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(nft), BURN - 1, BURN)
        );
        nft.mint(0);
        vm.stopPrank();

        // Approval but no balance.
        vm.startPrank(carol);
        vimd.approve(address(nft), BURN);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, carol, 0, BURN));
        nft.mint(0);
        vm.stopPrank();
        assertEq(nft.totalMinted(), 0);
    }

    function test_burnMintInvalidFinalistReverts() public {
        vm.startPrank(alice);
        vimd.approve(address(nft), BURN);
        vm.expectRevert(abi.encodeWithSelector(BrandGenesisNFT.InvalidFinalist.selector, 3));
        nft.mint(3);
        vm.stopPrank();
        assertEq(vimd.balanceOf(DEAD), 0);
    }

    function test_burnMintCapIsTwoThousand() public {
        vimd.transfer(alice, 2001 * BURN);
        vm.startPrank(alice);
        vimd.approve(address(nft), type(uint256).max);
        for (uint256 i; i < 2000; ++i) {
            nft.mint(uint8(i % 3));
        }
        assertEq(nft.totalBurnMints(), 2000);
        vm.expectRevert(BrandGenesisNFT.BurnMintCapReached.selector);
        nft.mint(0);
        vm.stopPrank();
        assertEq(vimd.balanceOf(DEAD), 2000 * BURN);

        // Votes are a separate cap and still work.
        vm.prank(bob);
        nft.vote(2, 1);
        assertEq(nft.ownerOf(2001), bob);
    }

    function test_tokenIdsSharedInMintOrder() public {
        vm.prank(alice);
        nft.vote(0, 0); // id 1
        vm.startPrank(bob);
        vimd.approve(address(nft), BURN);
        nft.mint(1); // id 2
        nft.vote(2, 2); // id 3
        vm.stopPrank();
        assertEq(nft.ownerOf(1), alice);
        assertEq(nft.ownerOf(2), bob);
        assertEq(nft.ownerOf(3), bob);
        assertTrue(nft.isVoteToken(1));
        assertFalse(nft.isVoteToken(2));
        assertTrue(nft.isVoteToken(3));
        assertEq(nft.totalMinted(), 3);
        assertEq(nft.totalSupply(), 3);
    }

    // ───────────────────────────── burn ─────────────────────────────

    function test_burnChangesNoVoteAndReturnsNoVimd() public {
        vm.prank(alice);
        nft.vote(0, 1);
        vm.startPrank(bob);
        vimd.approve(address(nft), BURN);
        nft.mint(1);
        vm.stopPrank();
        uint256 bobBefore = vimd.balanceOf(bob);
        uint256 deadBefore = vimd.balanceOf(DEAD);

        vm.expectEmit(true, true, true, true);
        emit Burned(1, alice);
        vm.prank(alice);
        nft.burn(1);
        vm.prank(bob);
        nft.burn(2);

        assertEq(nft.votes(1), 1, "vote kept");
        assertTrue(nft.seatVoted(0), "seat still used");
        assertEq(nft.leader(), 1);
        assertEq(nft.totalBurned(), 2);
        assertEq(nft.totalMinted(), 2);
        assertEq(nft.totalSupply(), 0);
        assertEq(nft.balanceOf(alice), 0);
        assertEq(vimd.balanceOf(bob), bobBefore, "no refund");
        assertEq(vimd.balanceOf(DEAD), deadBefore, "dead balance unchanged");
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 1));
        nft.ownerOf(1);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 1));
        nft.tokenURI(1);
        // The id is never reused.
        vm.prank(bob);
        nft.vote(2, 0);
        assertEq(nft.ownerOf(3), bob);
    }

    function test_burnByStrangerReverts() public {
        vm.prank(alice);
        nft.vote(0, 0);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, bob, 1));
        nft.burn(1);
        assertEq(nft.ownerOf(1), alice);
    }

    function test_burnByApprovedAndOperator() public {
        vm.startPrank(alice);
        nft.vote(0, 0);
        nft.vote(1, 0);
        nft.approve(bob, 1);
        nft.setApprovalForAll(carol, true);
        vm.stopPrank();
        vm.prank(bob);
        nft.burn(1);
        vm.prank(carol);
        nft.burn(2);
        assertEq(nft.totalBurned(), 2);
        assertEq(nft.votes(0), 2);
    }

    function test_burnNonexistentReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 5));
        nft.burn(5);
    }

    // ───────────────────────────── leader / winner ─────────────────────────────

    function test_leaderRevertsWithNoVotes() public {
        vm.expectRevert(BrandGenesisNFT.NoVotes.selector);
        nft.leader();
    }

    function test_winnerRevertsBeforeVoteEnd() public {
        vm.prank(alice);
        nft.vote(0, 2);
        vm.expectRevert(BrandGenesisNFT.VotingOpen.selector);
        nft.winner();
        vm.warp(nft.VOTE_END() - 1);
        vm.expectRevert(BrandGenesisNFT.VotingOpen.selector);
        nft.winner();
        vm.warp(nft.VOTE_END());
        assertEq(nft.winner(), 2);
    }

    function test_winnerRevertsWithZeroVotes() public {
        vm.warp(nft.VOTE_END());
        vm.expectRevert(BrandGenesisNFT.NoVotes.selector);
        nft.winner();
        // Burn mints never create a winner.
        vm.startPrank(alice);
        vimd.approve(address(nft), BURN);
        nft.mint(0);
        vm.stopPrank();
        vm.expectRevert(BrandGenesisNFT.NoVotes.selector);
        nft.winner();
    }

    function test_leaderAndWinnerTieBreakLowestIndex() public {
        vm.prank(bob);
        nft.vote(2, 2); // C: 1
        assertEq(nft.leader(), 2);
        vm.prank(alice);
        nft.vote(0, 1); // B: 1, C: 1 -> B
        assertEq(nft.leader(), 1);
        vm.prank(carol);
        nft.vote(1999, 0); // A: 1, B: 1, C: 1 -> A
        assertEq(nft.leader(), 0);
        vm.prank(alice);
        nft.vote(1, 2); // C: 2 -> C
        assertEq(nft.leader(), 2);

        vm.warp(nft.VOTE_END());
        assertEq(nft.winner(), 2);
    }

    function test_winnerTieBreakWithTwoWay() public {
        vm.prank(alice);
        nft.vote(0, 2);
        vm.prank(bob);
        nft.vote(2, 1);
        vm.warp(nft.VOTE_END() + 1);
        assertEq(nft.winner(), 1, "B beats C on a tie");
        assertEq(nft.leader(), 1);
    }

    // ───────────────────────────── tokenURI ─────────────────────────────

    function test_tokenURIVoteDecodesToValidJsonAndSvg() public {
        vm.prank(alice);
        nft.vote(1, 1);
        string memory json = _decodeJson(nft.tokenURI(1));

        assertEq(vm.parseJsonString(json, ".name"), "Visual Identity Genesis #1");
        assertEq(vm.parseJsonString(json, ".attributes[0].trait_type"), "Edition");
        assertEq(vm.parseJsonString(json, ".attributes[0].value"), "1");
        assertEq(vm.parseJsonString(json, ".attributes[1].trait_type"), "Finalist");
        assertEq(vm.parseJsonString(json, ".attributes[1].value"), "B");
        assertEq(vm.parseJsonString(json, ".attributes[2].trait_type"), "Type");
        assertEq(vm.parseJsonString(json, ".attributes[2].value"), "Vote");
        assertEq(vm.parseJsonString(json, ".attributes[3].trait_type"), "Seat");
        assertEq(vm.parseJsonString(json, ".attributes[3].value"), "1");
        assertEq(vm.parseJsonString(json, ".attributes[4].trait_type"), "Number");
        assertEq(vm.parseJsonString(json, ".attributes[4].value"), "1");

        string memory svg = _decodeImage(vm.parseJsonString(json, ".image"));
        assertEq(svg, artB.logomark(), "image is finalist B's logomark, byte for byte");
    }

    function test_tokenURIBurnDecodesToValidJsonAndSvg() public {
        vm.startPrank(alice);
        vimd.approve(address(nft), BURN * 2);
        nft.mint(0);
        nft.mint(2);
        vm.stopPrank();

        string memory json = _decodeJson(nft.tokenURI(2));
        assertEq(vm.parseJsonString(json, ".name"), "Visual Identity Genesis #2");
        assertEq(vm.parseJsonString(json, ".attributes[1].value"), "C");
        assertEq(vm.parseJsonString(json, ".attributes[2].value"), "Burn");
        assertEq(vm.parseJsonString(json, ".attributes[3].trait_type"), "Number");
        assertEq(vm.parseJsonString(json, ".attributes[3].value"), "2");
        // No Seat attribute on a burn mint.
        assertFalse(vm.keyExistsJson(json, ".attributes[4]"));
        assertEq(_decodeImage(vm.parseJsonString(json, ".image")), artC.logomark());

        json = _decodeJson(nft.tokenURI(1));
        assertEq(vm.parseJsonString(json, ".attributes[1].value"), "A");
        assertEq(_decodeImage(vm.parseJsonString(json, ".image")), artA.logomark());
    }

    function test_tokenURIUnmintedReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 1));
        nft.tokenURI(1);
    }

    function _decodeJson(string memory uri) internal pure returns (string memory) {
        return string(Base64Decoder.decode(uri.stripPrefix("data:application/json;base64,")));
    }

    function _decodeImage(string memory image) internal pure returns (string memory svg) {
        svg = string(Base64Decoder.decode(image.stripPrefix("data:image/svg+xml;base64,")));
        bytes memory s = bytes(svg);
        assertTrue(s.length > 11, "svg too short");
        assertEq(string(abi.encodePacked(s[0], s[1], s[2], s[3])), "<svg");
    }

    function assertTrue(bool v, string memory m) internal pure override {
        require(v, m);
    }
}
