# VisualIdentity.md, Edition 1: contracts

A community proposal for IMD's visual identity, offered to the IMD team to adopt, adapt or ignore.
Not official IMD branding. Three finalist brand guides compete; identity.md seat holders pick the
winner, one vote per seat id, by minting an NFT of the guide they back. Everything here is CC0.

This repository is the contract stage of the approved workflow: the launch token, the three on-chain
art contracts, the vote/collector NFT, their tests and ABI exports. The website and the brand guides
are separate stages. The launch itself (source publication, attestation, admission, deployment) is
performed by IMD's ProjectFactory after this stage is accepted; nothing here deploys anything.

## Contracts

| Solidity name     | File                      | Purpose                                                        |
| ----------------- | ------------------------- | -------------------------------------------------------------- |
| `LaunchToken`     | `src/LaunchToken.sol`     | VIMD, the fixed-supply launch token                            |
| `FinalistArtA`    | `src/FinalistArtA.sol`    | Returns `art/finalist-a/logomark.svg` byte for byte            |
| `FinalistArtB`    | `src/FinalistArtB.sol`    | Returns `art/finalist-b/logomark.svg` byte for byte            |
| `FinalistArtC`    | `src/FinalistArtC.sol`    | Returns `art/finalist-c/logomark.svg` byte for byte            |
| `BrandGenesisNFT` | `src/BrandGenesisNFT.sol` | ERC-721 "Visual Identity Genesis" (VIMDG): votes and burn mints |

ABI exports: `docs/abi/<Contract>.json` (generated with `forge inspect <Contract> abi --json`).

### LaunchToken (VIMD)

- ERC-20 `VisualIdentity.md` / `VIMD`, 18 decimals, exactly 1,000,000,000 tokens (10^27 minor
  units) minted once to `msg.sender` (the factory) in the constructor. No constructor arguments.
- No mint, owner, pause, blocklist, fee or upgrade functions. Plain OpenZeppelin v5 ERC-20.
- The factory splits the supply at launch: 10% to the swarm's MerkleDistributor, 90% to the pool.
  The brief's "none to the requester" is satisfied by the launch's 90% pool share; the token itself
  allocates nothing to anyone and no contract here is sent any of it at launch.
- What the brief does not get from this token: nothing beyond the standard was asked. The pool fee,
  its pairing with IMD and the opening price are the launch's, not the token's; the token carries no
  fee logic.

### FinalistArtA / B / C

Stateless, ownerless contracts implementing `IFinalistArt`:

- `logomark()` returns the finalist's logomark SVG as a string constant.
- `finalist()` returns "A", "B" or "C".

The constants are the exact bytes of `art/finalist-{a,b,c}/logomark.svg` (no trailing newline), and
`test/FinalistArt.t.sol` pins them. **Operational note for the brand-guide stage:** this repository
started empty, so the three logomarks here (Keystone, Orbit, Lattice: original geometric marks,
paths and basic shapes only, each under 1 KB) are the Edition 1 marks the contracts ship with. If the
brand-guide stage replaces a logomark, the matching `SVG` constant in `src/FinalistArt<X>.sol` and
the expected string in `test/FinalistArt.t.sol` must be updated to the new file's exact bytes before
the manifest is written, because the art contracts are immutable once deployed.

### BrandGenesisNFT (VIMDG)

ERC-721 `Visual Identity Genesis`, symbol `VIMDG`, OpenZeppelin v5. Immutable by design: no owner,
admin, pause, upgrade, setters or withdraw. It never holds VIMD or ETH.

Constructor (5 address arguments, no owner, calls no contract):

| Argument | Manifest value                               | Meaning                                       |
| -------- | -------------------------------------------- | --------------------------------------------- |
| `vimd`   | `$token`                                     | The launch token burned by `mint`             |
| `seats`  | `0x0000ec93127baa929e58e97dd0095a2bfb38ec1d` | identity.md seat collection (from the brief)  |
| `artA`   | `$contract:FinalistArtA`                     | Finalist 0 art                                |
| `artB`   | `$contract:FinalistArtB`                     | Finalist 1 art                                |
| `artC`   | `$contract:FinalistArtC`                     | Finalist 2 art                                |

Zero addresses are refused. Addresses are not checked for code (the launch checks run on an empty
chain); the seat collection and token are used on first call.

Behaviour:

- `vote(uint256 seatId, uint8 finalist)`: finalist 0-2, `block.timestamp < VOTE_END`, seat id
  0-1999, seat never voted, `SEATS.ownerOf(seatId) == msg.sender`. Marks the seat used forever
  (survives seat transfers and NFT burns), mints the next token id to the caller with `_mint`,
  records its finalist and seat, adds one vote. At most 2,000 vote mints.
- `mint(uint8 finalist)`: anyone, any time, finalist 0-2. Transfers exactly 50,000 VIMD
  (`BURN_AMOUNT = 50000 * 10^18`) from the caller to `0x000000000000000000000000000000000000dEaD`
  with `safeTransferFrom`, then mints the next token id with `_mint`. Never a vote. At most 2,000
  burn mints. Requires a prior VIMD approval of at least 50,000 VIMD to the NFT contract.
- Token ids run 1-4,000 in mint order, shared by both kinds. Ids are never reused.
- `VOTE_END = deployment timestamp + 7 days` (`VOTE_DURATION`), an immutable.
- `leader()`: most-voted finalist so far, lowest index on a tie; reverts `NoVotes()` with no votes.
- `winner()`: reverts `VotingOpen()` while `block.timestamp < VOTE_END`, otherwise `leader()`
  (so it reverts `NoVotes()` if nobody voted).
- `burn(uint256 id)`: by the owner, an approved address or an approved operator. Returns no VIMD,
  changes no vote and no `seatVoted`. Increments `totalBurned`. For later editions.
- `tokenURI(id)`: `data:application/json;base64,` of a JSON document with `name`
  "Visual Identity Genesis #<id>", a description, `image` as `data:image/svg+xml;base64,` of the
  finalist's logomark, and attributes Edition (1), Finalist (A/B/C), Type (Vote/Burn), Seat (vote
  mints only) and Number (the token id). Reverts for burned or unminted ids.
- Views: `totalMinted`, `totalBurned`, `totalSupply` (live tokens), `totalVoteMints`,
  `totalBurnMints`, `totalVotes`, `votes(uint8)`, `seatVoted(uint256)`, `finalistOf(uint256)`,
  `isVoteToken(uint256)`, `seatOf(uint256)`, `artOf(uint8)`, `votingOpen()`, `EDITION = 1`,
  `VOTE_END`, `MAX_SEAT_ID = 1999`, `MAX_VOTE_MINTS = 2000`, `MAX_BURN_MINTS = 2000`.
- Events: `Voted(seatId, finalist, voter, tokenId)`, `BurnMinted(minter, finalist, tokenId,
  vimdBurned)`, `Burned(tokenId, by)`, plus the ERC-721 events.

Custom errors: `InvalidFinalist`, `InvalidSeat`, `NotSeatOwner`, `SeatAlreadyVoted`,
`VotingClosed`, `VotingOpen`, `NoVotes`, `VoteMintCapReached`, `BurnMintCapReached`, `ZeroAddress`.

## Chosen values (the brief left these open)

| Constant         | Value   | Where                     |
| ---------------- | ------- | ------------------------- |
| `VOTE_DURATION`  | 7 days  | `BrandGenesisNFT`         |
| `MAX_SEAT_ID`    | 1999    | `BrandGenesisNFT`         |
| `MAX_VOTE_MINTS` | 2000    | `BrandGenesisNFT`         |
| `MAX_BURN_MINTS` | 2000    | `BrandGenesisNFT`         |
| `BURN_AMOUNT`    | 50,000 VIMD | `BrandGenesisNFT`     |
| "Number" attribute | the token id | `tokenURI`           |

The first five come straight from the brief; "Number" is the one interpretation made here.

## Launch parameters (for the manifest stage, not written here)

- Chain: Ethereum mainnet (chain id 1). Pair: IMD (`0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`).
- Pool: fee 12500, tick spacing 60, initial price `79228162514264337593543950336`; the deployer
  derives the real opening price from the policy's opening market cap.
- Launch token: `LaunchToken`. Application contracts in dependency order: `FinalistArtA`,
  `FinalistArtB`, `FinalistArtC` (no arguments), then `BrandGenesisNFT` with the five arguments
  above. No contract takes `$owner`; none has an owner.
- The factory also deploys the MerkleDistributor and PoolInitializationGuard; they are not here.
- `launch.json` is written by the manifest stage after acceptance. Do not add one to this tree.

## After launch

Nothing to configure. No contract has an owner, setter or outside dependency to fill in: the seat
collection is a constructor argument from the brief, the token is `$token`, and the art contracts
are `$contract:` references. The only operational duty is to keep the art contracts' SVG constants
equal to the published logomarks before the manifest is written (see above).

## Assumptions and trust

- **Seat collection.** `0x0000ec93127baa929e58e97dd0095a2bfb38ec1d` is taken from the approved
  workflow and is not verified against the chain here (no network at verification). `ownerOf` is
  reached by STATICCALL; a seat held by a contract can only vote if that contract calls `vote`.
- **Votes belong to seat ids, not people.** Seats can be bought before voting; each id votes once
  ever. Seats are concentrated in a few hundred wallets, some holding dozens.
- **Burned VIMD is gone.** `mint` sends it to the dead address; nobody can recover it.
- **No admin.** Nothing can pause, extend, re-run or correct the vote. A winner with few votes is
  still the winner; zero votes means `winner()` reverts forever.
- **Timing.** `VOTE_END` is a fixed timestamp set at deployment. Validators can skew
  `block.timestamp` by seconds, which is immaterial for a 7-day window.
- **Reentrancy.** `vote` performs all state changes before `_mint` (no receiver callback) and reads
  the seat collection through a view call; a reentrant seat collection is tested. `mint` moves the
  VIMD through `SafeERC20` on the launch's own plain ERC-20; the NFT never holds tokens.
- **Immutability.** No proxies, DELEGATECALL, CALLCODE or SELFDESTRUCT; all library functions are
  internal, so the bytecode is unlinked and reproducible (`bytecode_hash = "none"`).
- **No audit.** Tests are not a security audit. IMD's review panel reviews this stage; there is no
  third-party audit.
- **The pool's 1% fee** goes to the wallet that paid for the launch and 0.25% to IMD, by the
  launch policy. The contracts contain no fee logic.

## Reproduce

Dependencies are vendored as plain files in `lib/` (forge-std v1.9.6, OpenZeppelin Contracts
v5.1.0). The compiler is pinned to `solc = "0.8.26"` in `foundry.toml`.

```sh
forge build
forge test
forge fmt --check
FOUNDRY_FUZZ_SEED=0x93ff23a2c617692c4af1b60b394b8213b4efa1fc48688f1bc06378dd896da1cd forge test
```

Tests (`test/`): `LaunchToken.t.sol` (supply, transfer, no mint), `FinalistArt.t.sol` (exact SVGs,
well-formedness), `BrandGenesisNFT.t.sol` with a mock seat collection (only the seat owner votes;
one vote per seat including after transfer and after burning the NFT; no votes at or after
`VOTE_END`; burn mints never change votes; both 2,000 caps; exact 50,000 VIMD burn and its failure
modes; tie-break in `leader` and `winner`; finalist 3 reverts; `burn(id)` changes no vote;
`winner()` reverts before `VOTE_END` and with zero votes; `tokenURI` decodes to JSON that
`vm.parseJson` accepts, whose image decodes to the finalist's exact SVG; reentrancy; no admin
surface), and `Deploy.t.sol` for the local deployment script.

`script/Deploy.s.sol` is for a fork or testnet rehearsal only (`deployAll(address seats)` is what
the test calls). The production deployment is IMD's and is not done from this repository.

## Deployed addresses

Filled in by the launch after deployment; none exist at this stage.

## Licence

CC0-1.0 for everything produced here. Vendored libraries keep their own licences (`lib/*/LICENSE*`).
