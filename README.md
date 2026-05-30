# vim-gst-debug
GStreamer log parsing and utils


## Large file optimizations

GStreamer logs can be very large files. This plugin follows unconventional practices to reduce friction and `vim` stalls. 

- Not setting types in `ftdetect`: instead, we directly source the vimscript files. Using `setfiletype` sends an event that other plugins (both native and user's) can listen to, wrecking havoc on load-time and stalling the editor even when just moving inside the buffer.
- The `copilot` plugin is disabled on the `gstreamerlogs` buffer type: Using it causes interruptions during insert mode, making edition impossible. This should be handled by the `copilot` plugin itself, or in second instance by the user's `.vimrc`. However, the stalls were so hard I made an exception and hardcoded an exception for this well-known plugin. Edition is not a primary task when following logs but being allowed to notes can be a valuable thinking tool.

