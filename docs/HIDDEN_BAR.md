# Hidden Bar placement

The separator must stay to the left of the arrow. Otherwise its expanded width
can hide Hidden Bar's own control when the bar collapses.

The repair uses new stable autosave identities for this pair on macOS 27 and
later, avoiding an older inverted arrangement. Positions reset once; hold
Command and drag the icons you want hidden to the separator's left afterward.
Older macOS versions keep their existing identities. App configuration, the
main menu item, network item and other applications' preferences are preserved.

Both items start compact; collapse is queued for the next main-queue turn.
Disablement, replacement or a user action invalidates stale queued work. This
queue boundary does not prove MenuBarAgent has finished placing the items.

## Manual acceptance before release

Use an isolated QA bundle/defaults domain. Expand an existing menu-bar manager
first, because its pusher can also hide the QA app's new icons.

- Confirm expanded order is separator-left, arrow-right.
- Click repeatedly and wait for 30-second automatic collapse. The arrow must
  remain visible and reachable, including after restart and disable/re-enable.
- Disable during initial installation and expand before queued collapse;
  deferred work must not restore removed items or override the user's action.
- Check notch, auto-hide and multiple-display layouts.

Controller tests cover compact installation, queued collapse, stable placement
identities and cancellation. They do not verify visible ordering.

Focused verification on macOS 27.0.1 passed using the actual repaired controller
in an isolated host: visible order, manual and 30-second automatic collapse,
restart and disable/re-enable. The arrow remained reachable on the notched
display. The full 563 XCTest cases and build passed. The original installed app
was restored afterward with identical configuration data. Multiple displays,
full auto-hide and wider hardware still require separate verification.

Apple documents [leftward status-item insertion](https://developer.apple.com/documentation/appkit/nsstatusbar/system),
[autosave identities](https://developer.apple.com/documentation/appkit/nsstatusitem/autosavename-swift.property)
and that [isVisible](https://developer.apple.com/documentation/appkit/nsstatusitem/isvisible)
can remain true when insufficient space hides an item.
