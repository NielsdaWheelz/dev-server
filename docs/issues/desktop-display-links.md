# desktop display connections

the november inventory targets simultaneous 3840 × 2160 at 120 hz on two dell
s2725qc monitors from the rtx 2080. the monitors have hdmi and usb-c with
displayport alt mode. the card's hdmi 2.0b output limits full-rgb refresh at
4k. the selected linux driver, cable and display modes need a physical test.
[dell manual](https://dl.dell.com/content/manual22980564-dell-s-27-4k-usb-c-monitor-s2725qc-user-s-guide.pdf?language=en-us),
[evga product sheet](https://cdn.cnetcontent.com/25/9f/259f0aa3-6403-40b1-9cde-ec08ac942ecb.pdf),
[nvidia usb-c display support](https://nvidia.custhelp.com/app/answers/detail/a_id/4711).

- connect the card's usb-c output to the first monitor with its supplied video cable.
- connect the card's displayport output to the second monitor with a cable
  specified for a displayport **source** and usb-c **display**, with hbr3 or
  better. check cable length for the planned floor placement. [bidirectional cable candidate](https://www.cablematters.com/pc-1836-124-40gbps-bi-directional-usb-c-to-displayport-21-cable.aspx).
- use the rear 65 w upstream usb-c port on both monitors. select usb-c input.
  if the target mode is missing, try the monitor's high-resolution usb-c
  prioritization setting.

close after recording both displays' simultaneous resolution, refresh, colour
format and vrr behavior, plus any accepted limits, in the
[desktop plan](../desktop.md#desktop-refurbishment).
