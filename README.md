# Isomorph

An Optimism based loans platform

## Motivation:

With the emergence of layer 2s and side-chains  in 2021 the cost of code complexity in EVM compatible blockchains has dropped dramatically. The new methods used to tackle financial derivatives have allowed the space to flourish with unique projects popping for every type of contract imaginable. 

Further building on this the reduced cost of transactions have also enabled a far greater, and cheaper, degree of composability. Yet many income generating products and unique assets have yet to be tapped into by protocols building on top of them. In doing so we aim to further increase the scope of what is possible for novel product design and flexibility afforded to the end user. 

This lack of inclusion is not without reason, the more complex a product the more likely it is to operate in a non-standard manner. This presents an obstacle to their integration in established loan projects as assets may require their own set of contracts to be integrated or pose unique risk profiles. 
Hence a bespoke platform that can specialise in these novel products is a logical choice.

## Design:

Isomorph aims to solve these issues by designing a platform by which novel asset holders can borrow a new stablecoin, MoUSD, using their asset as collateral against which the lending is secured. The protocol mints MoUSD into existence as required relieving the need for a counterparty providing USD capital, this enables a greater degree of control over interest rates that can be tailored to demand. 

When assets are deposited the user will be able to mint moUSD at varying ratios to the asset value, dependant on how volatile their price tends to be. 

At launch Isomorph will support several Synthetix synths, Lyra Option Pool tokens on Optimism and some Velodrome liquidity tokens with plans to expand these ranges of novel assets as well as including other protocols.

 By using moUSD loans liquidity providers will be able to leverage their exposure to pools and so compound their returns, gaining better returns on their employed capital. Alternative they can use the loan for tax management (dependent on location) and daily costs while letting the underlying collateral appreciate. This general strategy shall be repeated for other platforms enabling sustainable returns to be generated for the Isomorph system. 

## Stability of MoUSD:

As borrowers will wish to use their MoUSD on other DeFi protocols it will vital to have a highly liquid trading pool composed of MoUSD and other popular stablecoins. This will be achieved via a Curve style Metapool consisting of MoUSD, and other stablecoins. To promote liquidity providing this pool shall be incentivized, though the source of these incentives has yet to be decided.

## Tests:

- Begin by cloning the repo
- Then run "yarn install" in the main directory to install all required packages
- Connect your API endpoints and privatekey using the .env file. See sample_env for details.

If you swap to a different network you will need to update the static addresses that the Vaults rely on for Lyra, Synthetix and Velodrome. 

- Update MOUSD_TIME_DELAY in `moUSDToken.sol` to a shorter time than it's expected 3 days value. This is necessary to test Vault_Lyra.sol and Vault_Synths.sol because both rely on external oracles which will break functionality if we skip 3 days ahead and do not update them, updating them is too convoluted so instead we just use a shorter timelock for testing.

- Then run "npx hardhat test" to run all tests. All tests should pass, occasionally the API will time out due to some of the tests taking a while to process, if this happens run again.

# Slither results
Running slither . --filter-paths "contracts/tests|node_modules|contracts/Migrations|contracts/helper|contracts/interfaces|contracts/ConfirmedOwnerWithProposal"
produces 218 results. The above paths were filtered due to either not being written by us or being irrelevant. 



## Definitions:

- synths: Any token offered by the Synthetix protocol, they are synthetic assets where their prices track the underlying original token/stock/commodity/currency. Redemption into any other synth is guaranteed by  SNX stakers who assume the debt pool risk ensuring the value of all issued synths. 

- sUSD:  A synth, based on the US dollar. Generally used as a gateway into and out of the Synthetix ecosystem owing to its stable price and inclusion in a Curve pool with other popular stablecoins USDC, USDT and Dai.

- Metapool: a liquidity pool design from Curve.fi comprised of a unique stablecoin attached to the 3pool Dai, USDC USDT Curve.fi liquidity pool design in order to provide a simple route into and out of the unique stablecoin. 

- Lyra: An options issuing protocol native to Optimism, currently offering options on ETH, BTC and SOL markets, with the ability to provide liquidity as a hedged option writer via their liquidity pools.

- Velodrome: An Automated Market Maker on Optimism based on the design of Solidly from Fantom. Offering trading of numerous token pairs and volatile as well as stable pairs, these liquidity pairs receive staking rewards in the form of VELO token rewards.  


