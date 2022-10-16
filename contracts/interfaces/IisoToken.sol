
pragma solidity =0.8.9;

interface IisoToken {
  function allocatedTokens ( address ) external view returns ( uint256 );
  function allowance ( address owner, address spender ) external view returns ( uint256 );
  function approve ( address spender, uint256 amount ) external returns ( bool );
  function balanceOf ( address account ) external view returns ( uint256 );
  function claimTokens (  ) external returns ( uint256 );
  function decimals (  ) external view returns ( uint8 );
  function decreaseAllowance ( address spender, uint256 subtractedValue ) external returns ( bool );
  function increaseAllowance ( address spender, uint256 addedValue ) external returns ( bool );
  function initialized (  ) external view returns ( bool );
  function lastCallTime ( address ) external view returns ( uint256 );
  function lockedTokens ( address ) external view returns ( uint256 );
  function name (  ) external view returns ( string memory);
  function symbol (  ) external view returns ( string memory);
  function tokensClaimable ( address _user, uint256 _epochTime ) external view returns ( uint256 );
  function totalSupply (  ) external view returns ( uint256 );
  function transfer ( address recipient, uint256 amount ) external returns ( bool );
  function transferFrom ( address sender, address recipient, uint256 amount ) external returns ( bool );
  function unlockedTokens ( address ) external view returns ( uint256 );
  function vestEnd (  ) external view returns ( uint256 );
  function vestLength (  ) external view returns ( uint256 );
}
