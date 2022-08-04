# Isomorph

Optimism based loans platform

## Motivation:

With the emergence of layer 2s and side-chains  in 2021 the cost of code complexity in EVM compatible blockchains has dropped dramatically. The new methods used to tackle financial derivatives have allowed the space to flourish with unique projects popping for every type of contract imaginable. 

Further building on this the reduced cost of transactions have also enabled a far greater, and cheaper, degree of composability. Yet many income generating products and unique assets have yet to be tapped into by protocols building on top of them. In doing so we aim to further increase the scope of what is possible for novel product design and flexibility afforded to the end user. 

This lack of inclusion is not without reason, the more complex a product the more likely it is to operate in a non-standard manner. This presents an obstacle to their integration in established loan projects as assets may require their own set of contracts to be integrated or pose unique risk profiles. 
Hence a bespoke platform that can specialise in these novel products is a logical choice.

## Design:

Isomorph aims to solve these issues by designing a platform by which novel asset holders can borrow a new stablecoin, MoUSD, using their asset as collateral against which the lending is secured. The protocol mints MoUSD into existence as required relieving the need for a counterparty providing USD capital, this enables a greater degree of control over interest rates that can be tailored to demand. 

When assets are deposited the user will be able to mint moUSD at varying ratios to the asset value, dependant on how volatile their price tends to be. At launch Isomorph will support several Synthetix synths and Lyra Option Pool tokens on Optimism with plans to expand to other novel assets such as DEX Liquidity Provider positions. By using moUSD loans liquidity providers of Lyra pools will be able to leverage their exposure to the options pools and so compound their returns, gaining better returns on their employed capital. This general strategy shall be repeated for other platforms enabling sustainable returns to be generated for the Isomorph system. 

## Stability of MoUSD:

As borrowers will wish to use their MoUSD on other DeFi protocols it will vital to have a highly liquid trading pool composed of MoUSD and other popular stablecoins. This will be achieved via a Curve style Metapool consisting of MoUSD, and other stablecoins. To promote liquidity providing this pool shall be incentivized, though the source of these incentives has yet to be decided.

## Tests:

Begin by cloning the repo,
Then run "yarn install" in the main directory to install all required packages
connect your API endpoints and privatekey using the .env file. See sample_env for details.
If you swap to a different network you will need to update the static addresses listed in contracts/vault.sol lines 63-90.
Then run "npx hardhat test" to run all tests. All tests should pass, occasionally the API will time out due to some of the tests taking a while to process, 
if this happens run again.

## Definitions:

- synths: Any token offered by the Synthetix protocol, they are synthetic assets where their prices track the underlying original token/stock/commodity/currency. Redemption into any other synth is guaranteed by  SNX stakers who assume the debt pool risk ensuring the value of all issued synths. 

- sUSD:  A synth, tracking the US dollar. Generally used as a gateway into and out of the Synthetix ecosystem owing to it's stable price and inclusion in a Curve pool with other popular stablecoins USDC, USDT and Dai.

- Metapool: a liquidity pool design from Curve.fi comprised of a unique stablecoin attached to the 3pool Dai, USDC USDT Curve.fi liquidity pool design in order to provide a simple route into and out of the unique stablecoin. 


