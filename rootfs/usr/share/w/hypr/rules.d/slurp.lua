-- slurp (region selection for w-screenshot's satty path and w-record, via
-- w-capture-lib). Owned by apply.sh --screencapture.
--
-- A layer rule, not a window rule: slurp is a layer-shell surface on the overlay
-- layer, namespace `selection`. W fades every layer out (animations.lua `layers`),
-- and grim/wf-recorder start the instant slurp exits — so a fading selection
-- would be captured into the very image it framed, dim and border included.
hl.layer_rule({ match = { namespace = "^(selection)$" }, no_anim = true })
