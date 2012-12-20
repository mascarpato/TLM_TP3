/********************************************************************
 * Copyright (C) 2009, 2012 by Verimag                              *
 * Initial author: Matthieu Moy                                     *
 * Modified by: Mauricio Altieri and João Leidens                   *
 ********************************************************************/

/*!
  \file hal.h
  \brief Harwdare Abstraction Layer : implementation for MicroBlaze
  ISS. 
*/

#ifndef HAL_H
#define HAL_H

#include <stdint.h>

/* Basic memory operations */
#define read_mem(a)     (*(uint32_t*)(a))
#define write_mem(a,d)  (*(uint32_t*)(a)) = (uint32_t)(d)

/* Nothing to do, just a simple polling loop. */
#define wait_for_irq()  while(!irq_received) cpu_relax();
#define cpu_relax()     void

/* Printf implemented for debugging purpose.
 * Send each character for the UART that performs the printf. 
 */
#define printf(x) int i = 0; \
                  for(i = 0; (char)x[i] != '\0'; \
                  (*(char*)(UART_BASEADDR + UART_FIFO_WRITE)) = ((char)x[i++]));

#endif /* HAL_H */
