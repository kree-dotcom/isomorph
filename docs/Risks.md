Using any smart contract is not risk free. When using Isomorph you are assuming
several risks:

- isoUSD depeg. If isoUSD depegs and its value falls below $1 then it is possible you will lose money if you were holding isoUSD or providing liquidity for a pool containing it and other stablecoins. This loss may be temporary or permanent depending on if it regains its peg.
If isoUSD depegs and its value rises above $1 then you may find it more expensive to repay any isoUSD loans you had taken out. 
The smart contracts themselves assume isoUSD always has a value of $1 and so when isoUSD depegs in either direction this does not affect liquidations at all.

- Composability risks. Isomorph is built on top of other protocols. If Synthetix or Lyra suffer an exploit then this may negatively affect assets in Isomorph. If the pricing functions of the collateral fail to be accurate then it may be possible for a safe loan to be liquidated by another person. Velo-Deposit-Tokens are another collateral which rely on the Velodrome system and Chainlink working correctly. 

- Multi-sig risks. Governance is decided currently by a multi-sig this is a 3 of 4 model and so is resistent to  up to 2 members of the multisig being compromised but a coordinated attack could lead to a governance attack. 
However important governance actions are delayed by a timelock of 3 days and so even if this were to  occur the community will have some time to react. 

- `setOpenLoanFee` could be abused by a malicious Admin address to front-run loan opening and charge a higher loan opening fee than intended. We have set a maximum loan open fee of 10% to mitigate the potential of this risk and the admin address will be a multi-sig to reduce the likelihood of malicious use. We would use a timelock for changing the loanOpenFee but due to the code size of some Vaults this is not possible.



 
