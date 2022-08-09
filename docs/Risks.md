Using any smart contract is not risk free. When using Isomorph you are assuming
several risks:

- moUSD depeg. If moUSD depegs and it's value falls below $1 then it is possible you will lose money if you were holding moUSD or providing liquidity for a pool containing it and other stablecoins. This loss may be temporary or permanent depending on if it regains it's peg.
If moUSD depegs and it's value rises above $1 then you may find it more expensive to repay any moUSD loans you had taken out. 
The smart contracts themselves assume moUSD always has a value of $1 and so when moUSD depegs in either direction this does not affect liquidations at all.

- Composability risks. Isomorph is built on top of other protocols. If Synthetix or Lyra suffer an exploit then this may negatively affect assets in Isomorph. If the pricing functions of the collateral fail to be accurate
then it may be possible for a safe loan to be liquidated by another person.

- Multi-sig risks. Governance is decided currently by a multi-sig this is a 3 of 5 model and so is resistent to  upto 2 members of the multisig being comprimised but a coordinated attack could lead to a governance attack. 
However important governance actions are delayed by a timelock of 3 days and so if this occurs the community will have some time to react. 




 
