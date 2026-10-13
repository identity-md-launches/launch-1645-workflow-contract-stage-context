// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC721Errors, IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {LaunchToken} from "../src/LaunchToken.sol";
import {FinalistArtA} from "../src/FinalistArtA.sol";
import {FinalistArtB} from "../src/FinalistArtB.sol";
import {FinalistArtC} from "../src/FinalistArtC.sol";
import {BrandGenesisNFT} from "../src/BrandGenesisNFT.sol";
import {MockSeats} from "./mocks/MockSeats.sol";
import {Base64Decoder} from "./utils/Base64Decoder.sol";

/// @notice A seat-holding contract with no ERC-721 receiver hook. Since the NFT mints with `_mint`,
///         such a holder can still vote and burn-mint; `_safeMint` would have locked it out.
contract HooklessHolder {
    function vote(BrandGenesisNFT nft, uint256 seatId, uint8 finalist) external {
        nft.vote(seatId, finalist);
    }

    function mint(BrandGenesisNFT nft, LaunchToken vimd, uint8 finalist) external {
        vimd.approve(address(nft), nft.BURN_AMOUNT());
        nft.mint(finalist);
    }
}

/// @notice A minter whose receiver hook re-enters `mint`. The hook is never invoked because the
///         contract mints with `_mint`, so the re-entry is never attempted and one mint costs one burn.
contract ReenteringReceiver {
    uint256 public hookCalls;

    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4) {
        hookCalls += 1;
        BrandGenesisNFT(msg.sender).mint(0);
        return this.onERC721Received.selector;
    }

    function mint(BrandGenesisNFT nft, LaunchToken vimd, uint8 finalist) external {
        vimd.approve(address(nft), type(uint256).max);
        nft.mint(finalist);
    }
}

/// @notice A seat collection whose `ownerOf` tries to re-enter `mint` and `burn`. Both are reached
///         through the STATICCALL `vote` makes, so any state change reverts and the vote fails whole.
contract ReentrantSeatsIntoMintAndBurn {
    BrandGenesisNFT public nft;
    uint8 public mode; // 0: re-enter mint, 1: re-enter burn

    function set(BrandGenesisNFT nft_, uint8 mode_) external {
        nft = nft_;
        mode = mode_;
    }

    function ownerOf(uint256) external view returns (address) {
        bytes memory data = mode == 0
            ? abi.encodeWithSelector(BrandGenesisNFT.mint.selector, uint8(0))
            : abi.encodeWithSelector(BrandGenesisNFT.burn.selector, uint256(1));
        (bool ok,) = address(nft).staticcall(data);
        require(ok, "reentry failed");
        return msg.sender;
    }
}

/// @notice Deploys the whole launch in one call, as the factory does in one transaction, and reports
///         where the supply sits afterwards.
contract OneShotDeployer {
    function deploy(address seats)
        external
        returns (LaunchToken token, BrandGenesisNFT nft, uint256 heldByDeployer, uint256 supply)
    {
        token = new LaunchToken();
        FinalistArtA a = new FinalistArtA();
        FinalistArtB b = new FinalistArtB();
        FinalistArtC c = new FinalistArtC();
        nft = new BrandGenesisNFT(address(token), seats, address(a), address(b), address(c));
        heldByDeployer = token.balanceOf(address(this));
        supply = token.totalSupply();
    }
}

/// forge-config: default.fuzz.runs = 512
contract BrandGenesisNFTAdversarialTest is Test {
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

    function setUp() public {
        vm.warp(1_800_000_000);
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

    function test_oneTransactionDeploymentLeavesSupplyWithDeployer() public {
        OneShotDeployer deployer = new OneShotDeployer();
        (LaunchToken token, BrandGenesisNFT deployed, uint256 held, uint256 supply) = deployer.deploy(address(seats));
        assertEq(supply, 10 ** 27);
        assertEq(held, supply, "constructors moved none of the launch supply");
        assertEq(token.balanceOf(address(deployed)), 0, "the NFT is allocated nothing at launch");
        assertEq(address(deployed.VIMD()), address(token));
        assertEq(deployed.VOTE_END(), block.timestamp + 7 days);
    }

    function test_voteEndIsFixedAtDeploymentNotFirstVote() public {
        uint256 end = nft.VOTE_END();
        vm.warp(block.timestamp + 3 days);
        vm.prank(alice);
        nft.vote(0, 0);
        assertEq(nft.VOTE_END(), end, "the window does not move with activity");
        vm.warp(end - 1);
        assertTrue(nft.votingOpen());
        vm.warp(end);
        assertFalse(nft.votingOpen());
    }

    function test_supportsStandardInterfacesOnly() public view {
        assertTrue(nft.supportsInterface(type(IERC165).interfaceId));
        assertTrue(nft.supportsInterface(type(IERC721).interfaceId));
        assertTrue(nft.supportsInterface(type(IERC721Metadata).interfaceId));
        assertFalse(nft.supportsInterface(0x780e9d63), "not enumerable");
        assertFalse(nft.supportsInterface(0xffffffff));
    }

    function test_artOfInvalidFinalistReverts() public {
        vm.expectRevert(abi.encodeWithSelector(BrandGenesisNFT.InvalidFinalist.selector, 3));
        nft.artOf(3);
        vm.expectRevert(abi.encodeWithSelector(BrandGenesisNFT.InvalidFinalist.selector, 255));
        nft.artOf(255);
    }

    // ───────────────────────────── seats and voting ─────────────────────────────

    function test_contractSeatHolderCanVoteWithoutReceiverHook() public {
        HooklessHolder holder = new HooklessHolder();
        seats.mint(address(holder), 10);
        holder.vote(nft, 10, 2);
        assertEq(nft.ownerOf(1), address(holder));
        assertEq(nft.votes(2), 1);
        assertTrue(nft.seatVoted(10));
    }

    function test_contractCanBurnMintWithoutReceiverHook() public {
        HooklessHolder holder = new HooklessHolder();
        vimd.transfer(address(holder), BURN);
        holder.mint(nft, vimd, 1);
        assertEq(nft.ownerOf(1), address(holder));
        assertEq(vimd.balanceOf(address(holder)), 0);
        assertEq(vimd.balanceOf(DEAD), BURN);
    }

    function test_receiverHookIsNeverInvokedSoItCannotReenter() public {
        ReenteringReceiver minter = new ReenteringReceiver();
        vimd.transfer(address(minter), 10 * BURN);
        minter.mint(nft, vimd, 0);
        assertEq(minter.hookCalls(), 0, "_mint does not call onERC721Received");
        assertEq(nft.totalMinted(), 1, "exactly one token for one burn");
        assertEq(vimd.balanceOf(DEAD), BURN);
        assertEq(vimd.balanceOf(address(minter)), 9 * BURN);
    }

    function test_reentrantSeatCollectionCannotReenterMintOrBurn() public {
        ReentrantSeatsIntoMintAndBurn evil = new ReentrantSeatsIntoMintAndBurn();
        BrandGenesisNFT target =
            new BrandGenesisNFT(address(vimd), address(evil), address(artA), address(artB), address(artC));

        evil.set(target, 0);
        vm.startPrank(alice);
        vimd.approve(address(target), type(uint256).max);
        vm.expectRevert("reentry failed");
        target.vote(0, 0);
        vm.stopPrank();
        assertEq(target.totalMinted(), 0);
        assertEq(vimd.balanceOf(DEAD), 0);

        evil.set(target, 1);
        vm.prank(alice);
        vm.expectRevert("reentry failed");
        target.vote(0, 0);
        assertEq(target.totalBurned(), 0);
    }

    function test_seatReturnedToOriginalOwnerStillCannotVote() public {
        vm.prank(alice);
        nft.vote(0, 0);
        vm.prank(alice);
        seats.transferFrom(alice, bob, 0);
        vm.prank(bob);
        seats.transferFrom(bob, alice, 0);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BrandGenesisNFT.SeatAlreadyVoted.selector, 0));
        nft.vote(0, 1);
        assertEq(nft.totalVotes(), 1);
    }

    function test_walletHoldingManySeatsVotesOncePerSeat() public {
        // Seat concentration: one wallet with dozens of seats casts one vote per seat, no more.
        for (uint256 id = 100; id < 140; ++id) {
            seats.mint(carol, id);
        }
        vm.startPrank(carol);
        for (uint256 id = 100; id < 140; ++id) {
            nft.vote(id, 1);
        }
        for (uint256 id = 100; id < 140; ++id) {
            vm.expectRevert(abi.encodeWithSelector(BrandGenesisNFT.SeatAlreadyVoted.selector, id));
            nft.vote(id, 2);
        }
        vm.stopPrank();
        assertEq(nft.votes(1), 40);
        assertEq(nft.balanceOf(carol), 40);
        assertEq(nft.totalVoteMints(), 40);
    }

    function test_votedSeatSoldThenBuyerCannotVoteButUnusedSeatCan() public {
        vm.prank(alice);
        nft.vote(0, 0);
        vm.startPrank(alice);
        seats.transferFrom(alice, bob, 0);
        seats.transferFrom(alice, bob, 1);
        vm.stopPrank();
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(BrandGenesisNFT.SeatAlreadyVoted.selector, 0));
        nft.vote(0, 2);
        nft.vote(1, 2);
        vm.stopPrank();
        assertEq(nft.votes(0), 1);
        assertEq(nft.votes(2), 1);
    }

    function test_voteRejectedAtEndDoesNotMarkSeat() public {
        vm.warp(nft.VOTE_END());
        vm.prank(alice);
        vm.expectRevert(BrandGenesisNFT.VotingClosed.selector);
        nft.vote(0, 0);
        assertFalse(nft.seatVoted(0));
        assertEq(nft.totalMinted(), 0);
    }

    function test_voteEventCarriesSharedTokenId() public {
        vm.startPrank(alice);
        vimd.approve(address(nft), BURN);
        nft.mint(0); // id 1
        vm.expectEmit(true, true, true, true);
        emit BrandGenesisNFT.Voted(1, 2, alice, 2);
        nft.vote(1, 2); // id 2
        vm.stopPrank();
        assertEq(nft.seatOf(2), 1);
        assertEq(nft.seatOf(1), 0, "burn mints record no seat");
        assertFalse(nft.isVoteToken(1));
    }

    // ───────────────────────────── burn mint ─────────────────────────────

    function test_mintWithExactBalanceSucceedsAndOneWeiShortFails() public {
        vm.startPrank(alice);
        vimd.transfer(carol, BURN);
        vm.stopPrank();
        vm.startPrank(carol);
        vimd.approve(address(nft), BURN);
        nft.mint(0);
        assertEq(vimd.balanceOf(carol), 0);
        assertEq(nft.ownerOf(1), carol);
        vm.stopPrank();

        address dave = makeAddr("dave");
        vm.prank(alice);
        vimd.transfer(dave, BURN - 1);
        vm.startPrank(dave);
        vimd.approve(address(nft), BURN);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, dave, BURN - 1, BURN));
        nft.mint(0);
        vm.stopPrank();
        assertEq(nft.totalMinted(), 1);
        assertEq(nft.totalBurnMints(), 1);
    }

    function test_unlimitedAllowanceIsNotConsumedButExactAllowanceIs() public {
        vm.startPrank(alice);
        vimd.approve(address(nft), type(uint256).max);
        nft.mint(0);
        assertEq(vimd.allowance(alice, address(nft)), type(uint256).max);
        vimd.approve(address(nft), 2 * BURN);
        nft.mint(1);
        assertEq(vimd.allowance(alice, address(nft)), BURN);
        nft.mint(2);
        assertEq(vimd.allowance(alice, address(nft)), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(nft), 0, BURN));
        nft.mint(2);
        vm.stopPrank();
        assertEq(vimd.balanceOf(DEAD), 3 * BURN);
        assertEq(nft.totalBurnMints(), 3);
    }

    function test_failedMintLeavesNoPartialState() public {
        vm.startPrank(alice);
        vimd.approve(address(nft), BURN);
        nft.mint(0); // id 1, consumes the allowance
        vm.expectRevert();
        nft.mint(0);
        vm.stopPrank();
        assertEq(nft.totalMinted(), 1, "the failed mint did not advance the id");
        assertEq(nft.totalBurnMints(), 1);
        assertEq(nft.finalistOf(2), 0);
        vm.prank(bob);
        nft.vote(2, 1);
        assertEq(nft.ownerOf(2), bob, "the next id is the one the failed mint would have taken");
    }

    function testFuzz_mintAlwaysCostsExactlyBurnAmount(uint256 allowance, uint256 extraBalance, uint8 finalist) public {
        allowance = bound(allowance, BURN, type(uint256).max);
        extraBalance = bound(extraBalance, 0, 1_000_000e18);
        finalist = uint8(bound(finalist, 0, 2));
        address minter = makeAddr("minter");
        vimd.transfer(minter, BURN + extraBalance);

        vm.startPrank(minter);
        vimd.approve(address(nft), allowance);
        nft.mint(finalist);
        vm.stopPrank();

        assertEq(vimd.balanceOf(minter), extraBalance, "exactly BURN left the minter");
        assertEq(vimd.balanceOf(DEAD), BURN, "exactly BURN reached dead");
        assertEq(vimd.balanceOf(address(nft)), 0);
        assertEq(nft.ownerOf(1), minter);
        assertEq(nft.finalistOf(1), finalist);
        assertEq(nft.totalVotes(), 0, "a burn mint is never a vote");
        if (allowance != type(uint256).max) {
            assertEq(vimd.allowance(minter, address(nft)), allowance - BURN);
        }
    }

    function testFuzz_mintRevertsWhenAllowanceOrBalanceShort(uint256 allowance, uint256 balance) public {
        // At least one of the two is short of BURN.
        allowance = bound(allowance, 0, 2 * BURN);
        balance = bound(balance, 0, 2 * BURN);
        if (allowance >= BURN && balance >= BURN) balance = BURN - 1;
        address minter = makeAddr("minter");
        if (balance > 0) vimd.transfer(minter, balance);

        vm.startPrank(minter);
        vimd.approve(address(nft), allowance);
        vm.expectRevert();
        nft.mint(0);
        vm.stopPrank();

        assertEq(nft.totalMinted(), 0);
        assertEq(nft.totalBurnMints(), 0);
        assertEq(vimd.balanceOf(minter), balance, "nothing moved");
        assertEq(vimd.balanceOf(DEAD), 0);
    }

    // ───────────────────────────── burn ─────────────────────────────

    function test_approvalClearedByTransferCannotBurn() public {
        vm.startPrank(alice);
        nft.vote(0, 0);
        nft.approve(bob, 1);
        nft.transferFrom(alice, carol, 1);
        vm.stopPrank();
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, bob, 1));
        nft.burn(1);
        assertEq(nft.ownerOf(1), carol);
        // The new holder may burn; the original voter no longer can.
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, alice, 1));
        nft.burn(1);
        vm.prank(carol);
        nft.burn(1);
        assertEq(nft.totalBurned(), 1);
        assertEq(nft.votes(0), 1, "the vote stays with the seat, not the token");
    }

    function test_burnedTokenCannotBeBurnedAgainOrMoved() public {
        vm.startPrank(alice);
        nft.vote(0, 0);
        nft.burn(1);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 1));
        nft.burn(1);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 1));
        nft.transferFrom(alice, bob, 1);
        vm.stopPrank();
        assertEq(nft.totalBurned(), 1, "a double burn did not count twice");
        assertEq(nft.totalSupply(), 0);
        assertEq(nft.finalistOf(1), 0);
        assertTrue(nft.isVoteToken(1), "the record survives the burn");
    }

    function test_burningEveryTokenDoesNotFreeSeatsOrChangeWinner() public {
        vm.prank(alice);
        nft.vote(0, 2);
        vm.prank(alice);
        nft.vote(1, 2);
        vm.prank(bob);
        nft.vote(2, 0);
        vm.startPrank(alice);
        nft.burn(1);
        nft.burn(2);
        vm.stopPrank();
        vm.prank(bob);
        nft.burn(3);
        assertEq(nft.totalSupply(), 0);
        assertEq(nft.leader(), 2);
        vm.warp(nft.VOTE_END());
        assertEq(nft.winner(), 2);
        vm.prank(alice);
        vm.expectRevert(BrandGenesisNFT.VotingClosed.selector);
        nft.vote(0, 0);
    }

    // ───────────────────────────── results ─────────────────────────────

    /// @dev Oracle from the brief: most votes wins, lowest index on a tie, revert with none.
    function testFuzz_leaderAndWinnerFollowTheTally(uint8 a, uint8 b, uint8 c) public {
        a = uint8(bound(a, 0, 12));
        b = uint8(bound(b, 0, 12));
        c = uint8(bound(c, 0, 12));
        uint256 next = 100;
        for (uint256 i; i < a; ++i) {
            seats.mint(carol, next);
            vm.prank(carol);
            nft.vote(next++, 0);
        }
        for (uint256 i; i < b; ++i) {
            seats.mint(carol, next);
            vm.prank(carol);
            nft.vote(next++, 1);
        }
        for (uint256 i; i < c; ++i) {
            seats.mint(carol, next);
            vm.prank(carol);
            nft.vote(next++, 2);
        }
        assertEq(nft.votes(0), a);
        assertEq(nft.votes(1), b);
        assertEq(nft.votes(2), c);
        assertEq(nft.totalVotes(), uint256(a) + b + c);

        vm.expectRevert(BrandGenesisNFT.VotingOpen.selector);
        nft.winner();

        if (a == 0 && b == 0 && c == 0) {
            vm.expectRevert(BrandGenesisNFT.NoVotes.selector);
            nft.leader();
            vm.warp(nft.VOTE_END());
            vm.expectRevert(BrandGenesisNFT.NoVotes.selector);
            nft.winner();
            return;
        }
        uint8 expected;
        if (b > a && b >= c) expected = 1;
        else if (c > a && c > b) expected = 2;
        else expected = 0;
        assertEq(nft.leader(), expected, "leader");
        vm.warp(nft.VOTE_END());
        assertEq(nft.winner(), expected, "winner");
    }

    // ───────────────────────────── metadata ─────────────────────────────

    function test_tokenURIUnchangedByTransferAndKeepsOriginalSeat() public {
        vm.prank(carol);
        nft.vote(1999, 2);
        string memory before = nft.tokenURI(1);
        vm.prank(carol);
        nft.transferFrom(carol, bob, 1);
        assertEq(nft.tokenURI(1), before, "metadata is bound to the token, not the holder");
        string memory json = string(Base64Decoder.decode(before.stripPrefix("data:application/json;base64,")));
        assertEq(vm.parseJsonString(json, ".attributes[3].trait_type"), "Seat");
        assertEq(vm.parseJsonString(json, ".attributes[3].value"), "1999");
        assertEq(vm.parseJsonString(json, ".attributes[1].value"), "C");
    }

    function testFuzz_tokenURIDecodesForEveryKindAndFinalist(uint8 finalist, bool asVote) public {
        finalist = uint8(bound(finalist, 0, 2));
        if (asVote) {
            vm.prank(alice);
            nft.vote(0, finalist);
        } else {
            vm.startPrank(alice);
            vimd.approve(address(nft), BURN);
            nft.mint(finalist);
            vm.stopPrank();
        }
        string memory json = string(Base64Decoder.decode(nft.tokenURI(1).stripPrefix("data:application/json;base64,")));
        assertEq(vm.parseJsonString(json, ".name"), "Visual Identity Genesis #1");
        assertEq(vm.parseJsonString(json, ".attributes[0].value"), "1");
        string memory letter = finalist == 0 ? "A" : finalist == 1 ? "B" : "C";
        assertEq(vm.parseJsonString(json, ".attributes[1].value"), letter);
        assertEq(vm.parseJsonString(json, ".attributes[2].value"), asVote ? "Vote" : "Burn");
        string memory svg =
            string(Base64Decoder.decode(vm.parseJsonString(json, ".image").stripPrefix("data:image/svg+xml;base64,")));
        assertEq(svg, nft.artOf(finalist).logomark(), "image is the finalist's exact logomark");
    }
}
