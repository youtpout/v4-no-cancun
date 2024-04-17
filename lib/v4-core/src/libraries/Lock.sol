// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {IHooks} from "../interfaces/IHooks.sol";

/// @notice This is a temporary library that allows us to use transient storage (sstore/sload)
/// TODO: This library can be deleted when we have the transient keyword support in solidity.
library Lock {
    // The slot holding the unlocked state, transiently. uint256(keccak256("Unlocked")) - 1;
    uint256 constant IS_UNLOCKED_SLOT = uint256(0xc090fc4683624cfc3884e9d8de5eca132f2d0ec062aff75d43c0465d5ceeab23);

    function unlock() internal {
        uint256 slot = IS_UNLOCKED_SLOT;
        assembly {
            // unlock
            sstore(slot, true)
        }
    }

    function lock() internal {
        uint256 slot = IS_UNLOCKED_SLOT;
        assembly {
            sstore(slot, false)
        }
    }

    function isUnlocked() internal view returns (bool unlocked) {
        uint256 slot = IS_UNLOCKED_SLOT;
        assembly {
            unlocked := sload(slot)
        }
    }
}
