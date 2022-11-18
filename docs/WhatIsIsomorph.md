# What is Isomorph.loans?

Isomorph is a layer 2 native lending platform that enables the borrowing of a new stablecoin isoUSD against the value of collateral assets, these loans are overcollateralized to ensure the value backing each loan exceeds the value of the given loan. 
isoUSD can then be swapped for other commonly accepted stablecoins and used elsewhere in DeFi. 

# How does it work?

- Loans are managed by their respective collateral's `Vault`, in which a user can open a new loan and close or modify an existing loan. 
Loans are liquidatable and because some collateral assets can be frozen and unable to trade there is a gap between the minimum Collateral to Loan ratio a user can open a loan at and the point at which the loan would become liquidatable. 

- Loans are isolated depending on their collateral and only one loan can be opened per address in each collateral. Trying to open another loan with the same collateral will simply modify the loan & collateral of the existing loan. Users are charged interest on loans this is handled by an opening fee and an annual rate that is proportionally charged every 3 minutes. 

- The Admin, currently a multi-sig wallet, can elect to add or modify collateral via the `CollateralBook`. All details relating to each collateral are stored in the CollateralBook. Adding a new collateral is instant but modifying a collateral's features requires a 3 day timelock to pass first. This timelock allows users to have adequate notice prior to the conditions of their loan changing. 

- Loans are made in a stablecoin called isoUSD, an ERC20 which contains a `MINTER` role that `Vaults` can be added to. Any address with the `MINTER` role can mint and burn isoUSD. This makes the design modular allowing the multi-sig to add new `Vaults` in order to support new collaterals. The addition of a new `MINTER` is also protected by a 3 day timelock  as a security measure. Removal of a `MINTER` role is instant as a precaution.

More details on the functions of each contract can be found in their respective sections. 
