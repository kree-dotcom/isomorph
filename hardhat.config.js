require("@nomiclabs/hardhat-waffle");
require("hardhat-interface-generator");
require('@symblox/hardhat-abi-gen');
require('hardhat-contract-sizer');

require('dotenv').config()

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
 
module.exports = {
  solidity: "0.8.9",
  
  settings: {
	optimizer : {
		enabled: true,
		runs: 2000,
		details: {
			yul: true, 
			yulDetails: {
				stackAllocation: true,
			}
		}
	}
  },
  networks: {
	hardhat: {
		forking: {
		  url: process.env.OPTIMISM_MAINNET_API_AND_KEY,
		  blockNumber: 13957420 //28047218  // 8th Oct 2022 
		  //main pin 13957420, 6th july //30th June 2022
		   //old pin 12185090 //18th June 2022
		}
	  },
  	kovan: {
  		url: process.env.KOVAN_API_AND_KEY,
  		accounts: [ process.env.DEPLOYMENT_ACCOUNT ]
  		},
	optimism: {
		url: process.env.OPTIMISM_MAINNET_API_AND_KEY,
		accounts: [ process.env.DEPLOYMENT_ACCOUNT ]
			},
  	    
	optimism_kovan: {
		url: process.env.OPTIMISM_KOVAN_API_AND_KEY,
		accounts: [ process.env.DEPLOYMENT_ACCOUNT ]
				},
	optimism_goerli: {
		url: process.env.OPTIMISM_GOERLI_API_AND_KEY,
		accounts: [ process.env.DEPLOYMENT_ACCOUNT ]
					}
				}	,
  	    
};

