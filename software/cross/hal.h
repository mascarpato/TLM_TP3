/********************************************************************
 * Copyright (C) 2009, 2012 by Verimag                              *
 * Initial author: Matthieu Moy                                     *
 ********************************************************************/

/*!
  \file hal.h
  \brief Harwdare Abstraction Layer : implementation for MicroBlaze
  ISS.

  
*/
#ifndef HAL_H
#define HAL_H

#include <stdint.h>


/* Dummy implementation of abort(): dereference a NULL pointer */
#define abort() ((*(int *)NULL) = 0)

/* TODO : implementer ces primitives pour la compilation croisée */
#define read_mem(a)     (*(uint32_t*)(a))
#define write_mem(a,d)  (*(uint32_t*)(a))=(uint32_t)(d)
#define wait_for_irq()  abort()
#define cpu_relax()     abort()


/* printf is disabled, for now ... 
    NOT MORE!!!!!!!!!!!*/
#define printf(x) NULL

void printf(

    write_mem

#endif /* HAL_H */
