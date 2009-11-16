/* GECKO3COM
 *
 * Copyright (C) 2008 by
 *   ___    ____  _   _
 *  (  _`\ (  __)( ) ( )   
 *  | (_) )| (_  | |_| |   Bern University of Applied Sciences
 *  |  _ <'|  _) |  _  |   School of Engineering and
 *  | (_) )| |   | | | |   Information Technology
 *  (____/'(_)   (_) (_)
 *
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details. 
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

/*********************************************************************/
/** \file     gecko3com_gpif.c
 *********************************************************************
 * \brief     project specific functions to handle the GPIF
 *
 *            
 *
 * \author    GNUradio team, Christoph Zimmermann bfh.ch
 * \date      2009-4-16
 *
 * \note Comments from the original GNU radio source: \n
 * The GPIF Designer tool is kind of screwed up, in that it doesn't 
 * configure some of the ports correctly.  We just use their tables and 
 * handle the initialization ourselves.  They also declare that their 
 * static initialized data is in xdata, which screws us too.
 *
*/

#include <stdint.h>
#include "gecko3com_gpif.h"
#include "gpif_data.h"
#include "isr.h"
#include "delay.h"
#include "fx2regs.h"
#include "gecko3com_regs.h"
#include "gecko3com_interfaces.h"
#include "syncdelay.h"
#include "debugprint.h"


/* These are the tables generated by the Cypress GPIF Designer */

/** \brief Waveform data generated by the Cypress GPIF Designer
 *
 *  this table is defined in the gpif_data.c file. provide the 
 *  desired file for your board
 */
extern const char WaveData[128];

/** \brief Flowstate data generated by the Cypress GPIF Designer
 *
 *  this table is defined in the gpif_data.c file. provide the 
 *  desired file for your board
 */
extern const char FlowStates[36];

/** \brief Init values generated by the Cypress GPIF Designer 
 *  and the edit-gpif script
 *
 *  this table is defined in the gpif_data.h file. provide the 
 *  desired file for your board
 */
extern const char InitData[7];


/** private flag to signal, that the GPIF receives data from the FPGA */
volatile static uint8_t flGPIF;



/** 
 * \brief exectuted when the gpif wafeform terminates 
 */
void
isr_gpif_done (void) interrupt
{
  ISR_DEBUG_PORT |= bmGPIF_DONE;

  clear_fifo_gpif_irq();

  if((flGPIF & bmGPIF_PENDING_DATA) == bmGPIF_PENDING_DATA) {
    flGPIF &= ~bmGPIF_PENDING_DATA;
    gpif_trigger_write();
  }
  else {
    INPKTEND = 0x06;
    gpif_trigger_read(); 
  }

  ISR_DEBUG_PORT &= ~bmGPIF_DONE;
}


/** 
 * \brief exectuted when data is available in the OUT endpoint 
 */
void
isr_endpoint_out_data (void) interrupt
{
  ISR_DEBUG_PORT |= bmFIFO_PF;

  clear_fifo_gpif_irq();

  if((GPIFIDLECTL & bmBIT3) == bmBIT3) {
    flGPIF |= bmGPIF_PENDING_DATA;
  }
  else {
    EA = 0;		/* disable all interrupts */
    GPIFABORT = 0xFF;
    SYNCDELAY;
    EA = 1;		/* global interrupt enable */

    gpif_trigger_write(); 
  }

  ISR_DEBUG_PORT &= ~bmFIFO_PF;
}


/** \brief initialize GPIF system */
void init_gpif (void)
{
  uint8_t i;

#ifdef GECKO3MAIN
  /* IFCLK is generated internally and runs at 48 MHz; GPIF "master mode" */
  IFCONFIG = bmIFCLKSRC | bm3048MHZ | bmIFCLKOE | bmGSTATE | bmIFGPIF;
  SYNCDELAY;

  /* we have to commit the currently processed packet BEFORE we switch to auto out mode */
  OUTPKTEND = bmSKIP | USB_TMC_EP_OUT;

  /*FIXME  only here for testing */
  EP6AUTOINLENH = (20) >> 8;	   SYNCDELAY;  /* this is the length for high speed */
  EP6AUTOINLENL = (20) & 0xff;  SYNCDELAY;
    
  /* enable autoout and autoin feature of the endpoints */
  EP2FIFOCFG |= bmAUTOOUT;
  SYNCDELAY;
  EP6FIFOCFG |= bmAUTOIN;
  SYNCDELAY;

  /* set endpoint 2 fifo (out) programmable flag to "higher or equal 3" 
   * we use the programmable flag as interrupt source to detect if data for the FPGA 
   * is available and as GPIF flag to stop the flowstate, for this the flag has to change
   * one cycle before the FIFO is completly empty, else we transfer one word too much */
  EP2FIFOPFH = bmDECIS;
  EP2FIFOPFL = 1;
  SYNCDELAY;

  EP2GPIFFLGSEL = bmFLAG_PROGRAMMABLE;
  // EP2GPIFFLGSEL = bmFLAG_EMPTY;
  SYNCDELAY;
  EP6GPIFFLGSEL = bmFLAG_FULL;
  SYNCDELAY;

  EP2GPIFPFSTOP = 0;
  EP6GPIFPFSTOP = 0;

#endif

  GPIFABORT = 0xFF;  /* abort any waveforms pending */
  SYNCDELAY;
 
  GPIFREADYCFG = InitData[ 0 ];
  GPIFCTLCFG = InitData[ 1 ];
  GPIFIDLECS = InitData[ 2 ];
  GPIFIDLECTL = InitData[ 3 ];
  /* Hmmm, what's InitData[ 4 ] ... */
  GPIFWFSELECT = InitData[ 5 ];
  /* GPIFREADYSTAT = InitData[ 6 ]; */	/* I think this register is read only... */
  
  for (i = 0; i < 128; i++){
    GPIF_WAVE_DATA[i] = WaveData[i];
  }

  setup_flowstate_common(); 

  FLOWSTATE = 0;		/* ensure it's off */

  GPIFREADYCFG |= bmINTRDY; /* set the internal ready signal */

  /* unset gpif flags */
  flGPIF = 0;
  

  EA = 0;		/* disable all interrupts */

  /* hook gpif interupt services */
  
  /* due to big problems with the done interrupt, we use the WAVEFORM interrupt
     to signal the firmware that the GPIF is done */
  hook_fgv(FGV_GPIFWF,(unsigned short) isr_gpif_done);
  hook_fgv(FGV_EP2PF,(unsigned short) isr_endpoint_out_data);

  EP2FIFOIE = bmFIFO_PF;
  GPIFIE = bmGPIFWF;
  
  EA = 1;		/* global interrupt enable */


  /* start gpif read, default state of the gpif to wait for fpga data */
  gpif_trigger_read();

}


/** \brief aborts any gpif running gpif transaction  */
void abort_gpif(void) {

#ifdef GECKO3MAIN
  
  /* signal an abort condition to the FPGA */
  //if(!(GPIFTRIG & bmGPIF_IDLE)) {
  //GPIFREADYCFG &= ~bmINTRDY;
  //udelay(10);
  //}
#endif
  EA = 0;		/* disable all interrupts */
  
  flGPIF = 0;

  GPIFABORT = 0xFF;
  SYNCDELAY;
  while(!(GPIFTRIG & bmGPIF_IDLE));
  print_info("gpif aborted\n");

  EA = 1;		/* global interrupt enable */


  gpif_trigger_read();
}


/** \brief disables gpif system */
void deactivate_gpif(void) {

#ifdef GECKO3MAIN
  
  /* signal an abort condition to the FPGA */
  //if(!(GPIFTRIG & bmGPIF_IDLE)) {
  //GPIFREADYCFG &= ~bmINTRDY;
  //udelay(10);
  //}
#endif


  EA = 0;		/* disable all interrupts */

  EP2FIFOIE = 0;  /* disable FIFO interrupt */
  SYNCDELAY;
  GPIFIE = 0;     /* disable all GPIF interrupts */
  SYNCDELAY;

  GPIFTCB0 = 0x00;
  EP2GPIFPFSTOP = 1;
  EP6GPIFPFSTOP = 1;

  GPIFABORT = 0xFF; /* abort pending GPIF transaction */
  SYNCDELAY;

  flGPIF = 0;  /* unset all internal GPIF flags */

#ifdef GECKO3MAIN
  //EP2FIFOCFG &= ~bmOEP;
  EP2FIFOCFG &= ~bmAUTOOUT;  /* disable AutoOUT feature */
  SYNCDELAY;
  //EP6FIFOCFG &= ~bmINFM;
  EP6FIFOCFG &= ~bmAUTOIN;   /* disable AutoIN feature */

#endif

  EA = 1;		/* global interrupt enable */


  print_info("gpif deactivated\n");
}
