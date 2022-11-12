# Isomorph

Isomorph is an Optimism naitve lending protocol where users can provide a variety of interest generating collaterals to mint the isoUSD stablecoin.

## Motivation:

With the emergence of layer 2s and side-chains  in 2021 the cost of code complexity in EVM compatible blockchains has dropped dramatically. The new methods used to tackle financial derivatives have allowed the space to flourish with unique projects popping for every type of contract imaginable. 

Further building on this the reduced cost of transactions have also enabled a far greater, and cheaper, degree of composability. Yet many income generating products and unique assets have yet to be tapped into by protocols building on top of them. In doing so we aim to further increase the scope of what is possible for novel product design and flexibility afforded to the end user. 

This lack of inclusion is not without reason, the more complex a product the more likely it is to operate in a non-standard manner. This presents an obstacle to their integration in established loan projects as assets may require their own set of contracts to be integrated or pose unique risk profiles. 
Hence a bespoke platform that can specialise in these novel products is a logical choice.

## Design:

Isomorph aims to solve these issues by designing a platform by which novel asset holders can borrow a new stablecoin, isoUSD, using their asset as collateral against which the lending is secured. The protocol mints isoUSD into existence as required relieving the need for a counterparty providing USD capital, this enables a greater degree of control over interest rates that can be tailored to demand. 

When assets are deposited the user will be able to mint isoUSD at varying ratios to the asset value, dependant on how volatile their price tends to be. 

At launch Isomorph will support several Synthetix synths, Lyra Option Pool tokens on Optimism and some Velodrome liquidity tokens with plans to expand these ranges of novel assets as well as including other protocols.

 By using isoUSD loans liquidity providers will be able to leverage their exposure to pools and so compound their returns, gaining better returns on their employed capital. Alternative they can use the loan for tax management (dependent on location) and daily costs while letting the underlying collateral appreciate. This general strategy shall be repeated for other platforms enabling sustainable returns to be generated for the Isomorph system. 

## Stability of isoUSD:

As borrowers will wish to use their isoUSD on other DeFi protocols it will vital to have a highly liquid trading pool allowing swapping of isoUSD to other popular stablecoins. This will be achieved via a Velodrome stable pool consisting of isoUSD and USDC. To promote liquidity providing this pool shall be incentivized, this will be achieved by a mixture of direct veVELO voting by Isomorph and bribes to incentivize other voters to vote for the pool. These votes in turn will result in VELO emissions being directed to the stakers of the isoUSD/USDC pool. 

## Tests and coverage:

- Begin by cloning the repo
- The repo contains a submodule so run `git submodule init && git submodule update` to get these files for Velo-Deposit-Tokens.
- Then run "yarn install" in the main directory to install all required packages
- Connect your API endpoints and privatekey using the .env file. See sample_env for details.

If you swap to a different network you will need to update the static addresses that the Vaults rely on for Lyra, Synthetix and Velodrome. 

- Update ISOUSD_TIME_DELAY in isoUSDToken.sol to a shorter time than it's expected 3 days value.  This is necessary to test Vault_Lyra.sol and Vault_Synths.sol because both rely on external oracles which will break functionality if we skip 3 days ahead and do not update them, updating them is too convoluted so instead we just use a shorter timelock for testing.

- Then run "yarn hardhat test" to run all tests. All tests should pass, occasionally the API will time out due to some of the tests taking a while to process, if this happens run again. The first test run will likely be much slower due to needing to fetch contract information at the fork block height. We use this block height for integration testing as we know all token doners have the balances we need to borrow at this height. If the block height is changed be aware tests using Synths or Lyra systems may fail if the respective external system's circuit breaker is in effect.

Coverage is currently as follows:
---------------------------------|----------|----------|----------|----------|----------------|
File                             |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
---------------------------------|----------|----------|----------|----------|----------------|
 contracts/                      |    97.73 |    86.65 |    94.87 |    96.41 |                |
  CollateralBook.sol             |       98 |    82.89 |    93.33 |    98.68 |             81 |
  ConfirmedOwnerWithProposal.sol |    33.33 |    33.33 |    42.86 |    35.29 |... 54,61,63,65 |
  Locker.sol                     |      100 |      100 |      100 |      100 |                |
  RoleControl.sol                |      100 |    85.71 |      100 |      100 |                |
  Vault_Lyra.sol                 |      100 |     88.1 |      100 |    97.55 |157,158,510,512 |
  Vault_Synths.sol               |      100 |    91.11 |      100 |    98.66 |        512,514 |
  Vault_Velo.sol                 |    98.15 |    87.27 |    96.43 |    97.01 |... 426,647,649 |
  isoUSDToken.sol                |      100 |      100 |      100 |      100 |                |
---------------------------------|----------|----------|----------|----------|----------------|
All files                        |    97.73 |    86.65 |    94.87 |    96.41 |                |
---------------------------------|----------|----------|----------|----------|----------------|

Please note ConfirmedOwnerWithProposal.sol was written by Chainlink and so can be ignored.



# Slither results
Running slither . --filter-paths "contracts/tests|node_modules|contracts/Migrations|contracts/helper|contracts/interfaces|contracts/ConfirmedOwnerWithProposal"
produces 218 results. The above paths were filtered due to either not being written by us or being irrelevant. 



## Definitions:

- synths: Any token offered by the Synthetix protocol, they are synthetic assets where their prices track the underlying original token/stock/commodity/currency. Redemption into any other synth is guaranteed by  SNX stakers who assume the debt pool risk ensuring the value of all issued synths. 

- sUSD:  A synth, based on the US dollar. Generally used as a gateway into and out of the Synthetix ecosystem owing to its stable price and inclusion in a Curve pool with other popular stablecoins USDC, USDT and Dai.

- Metapool: a liquidity pool design from Curve.fi comprised of a unique stablecoin attached to the 3pool Dai, USDC USDT Curve.fi liquidity pool design in order to provide a simple route into and out of the unique stablecoin. 

- Lyra: An options issuing protocol native to Optimism, currently offering options on ETH, BTC and SOL markets, with the ability to provide liquidity as a hedged option writer via their liquidity pools.

- Velodrome: An Automated Market Maker on Optimism based on the design of Solidly from Fantom. Offering trading of numerous token pairs and volatile as well as stable pairs, these liquidity pairs receive staking rewards in the form of VELO token rewards.  


