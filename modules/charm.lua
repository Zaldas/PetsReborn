-- modules/charm.lua
-- BST charm pet-specific elements: MP bar (when mob has MP) + ability recast rows (including Stay as isHealTimer slot).
-- Timer (charm duration countdown) is drawn by core.lua from the pet.timer token.

return (require('modules/petModule').new({ mp = true, mpNeedsHasMp = true }))
