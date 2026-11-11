-- modules/avatar.lua
-- SMN avatar-specific elements: MP bar + ability recast rows.
-- Registers 'mp' in posRegistry so core.lua can anchor TP dynamically.

return (require('modules/petModule').new({ mp = true, mpNeedsHasMp = true }))
