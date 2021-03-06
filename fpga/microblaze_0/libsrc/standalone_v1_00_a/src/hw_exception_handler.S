/*///////////////////////////////////////////////////////////////////////////
//
// Copyright (c) 2004 Xilinx, Inc.  All rights reserved.
//
// Xilinx, Inc.
// XILINX IS PROVIDING THIS DESIGN, CODE, OR INFORMATION "AS IS" AS A
// COURTESY TO YOU.  BY PROVIDING THIS DESIGN, CODE, OR INFORMATION AS
// ONE POSSIBLE   IMPLEMENTATION OF THIS FEATURE, APPLICATION OR
// STANDARD, XILINX IS MAKING NO REPRESENTATION THAT THIS IMPLEMENTATION
// IS FREE FROM ANY CLAIMS OF INFRINGEMENT, AND YOU ARE RESPONSIBLE
// FOR OBTAINING ANY RIGHTS YOU MAY REQUIRE FOR YOUR IMPLEMENTATION.
// XILINX EXPRESSLY DISCLAIMS ANY WARRANTY WHATSOEVER WITH RESPECT TO
// THE ADEQUACY OF THE IMPLEMENTATION, INCLUDING BUT NOT LIMITED TO
// ANY WARRANTIES OR REPRESENTATIONS THAT THIS IMPLEMENTATION IS FREE
// FROM CLAIMS OF INFRINGEMENT, IMPLIED WARRANTIES OF MERCHANTABILITY
// AND FITNESS FOR A PARTICULAR PURPOSE.
//
// $Id: hw_exception_handler.S,v 1.7 2005/08/09 01:50:48 vasanth Exp $
//
//////////////////////////////////////////////////////////////////////////////*/

/*
 * Microblaze HW Exception Handler
 * - Non self-modifying exception handler for the following exception conditions
 *   - Unalignment
 *   - Instruction bus error
 *   - Data bus error
 *   - Illegal instruction opcode
 *   - Divide-by-zero
 */

#include "microblaze_exceptions_g.h"
        
/* Helpful Macros */
#define EX_HANDLER_STACK_SIZ            (4*19)
#define RMSR_OFFSET                     0       
#define REG_OFFSET(regnum)              (4*regnum)
#define NUM_TO_REG(num)                 r ## num

#define R3_TO_STACK(regnum)             swi     r3, r1, REG_OFFSET(regnum)
#define R3_FROM_STACK(regnum)           lwi     r3, r1, REG_OFFSET(regnum)      

#define PUSH_REG(regnum)                swi     NUM_TO_REG(regnum), r1, REG_OFFSET(regnum)
#define POP_REG(regnum)                 lwi     NUM_TO_REG(regnum), r1, REG_OFFSET(regnum)
        
/* Uses r5 */
#define PUSH_MSR                                                                \
        mfs     r5, rmsr;                                                       \
        swi     r5, r1, RMSR_OFFSET;

#define PUSH_MSR_AND_ENABLE_EXC                                                 \
        mfs     r5, rmsr;                                                       \
        swi     r5, r1, RMSR_OFFSET;                                            \
        ori     r5, r5, 0x100;                          /* Turn ON the EE bit*/ \
        mts     rmsr, r5;
        
/* Uses r5 */
#define POP_MSR                                                                 \
        lwi     r5, r1, RMSR_OFFSET;                                            \
        mts     rmsr, r5;       

#define LWREG_NOP                                                               \
        bri     ex_handler_unhandled;                                           \
        nop;

#define SWREG_NOP                                                               \
        bri     ex_handler_unhandled;                                           \
        nop;        
        
/* r3 is the source */
#define R3_TO_LWREG_V(regnum)                                                   \
        R3_TO_STACK (regnum);                                                   \
        bri     ex_handler_done; 

/* r3 is the source */
#define R3_TO_LWREG(regnum)                                                     \
        or      NUM_TO_REG (regnum), r0, r3;                                    \
        bri     ex_handler_done;                        

/* r3 is the target */          
#define SWREG_TO_R3_V(regnum)                                                   \
        R3_FROM_STACK (regnum);                                                 \
        bri     ex_sw_tail;                                                     
                
/* r3 is the target */  
#define SWREG_TO_R3(regnum)                                                     \
        or      r3, r0, NUM_TO_REG (regnum);                                    \
        bri     ex_sw_tail; 

/* regnum is the source */  
#define FP_EX_OPB_SAVE(regnum)                                                  \
        swi     NUM_TO_REG (regnum), r0, mb_fpex_op_b;                          \
        nop;                                                                    \
        bri     handle_fp_ex_opa; 

/* regnum is the source */  
#define FP_EX_OPB_SAVE_V(regnum)                                                \
        R3_FROM_STACK (regnum);                                                 \
        swi     r3, r0, mb_fpex_op_b;                                           \
        bri     handle_fp_ex_opa; 
        
/* regnum is the source */  
#define FP_EX_OPA_SAVE(regnum)                                                  \
        swi     NUM_TO_REG (regnum), r0, mb_fpex_op_a;                          \
        nop;                                                                    \
        bri     handle_fp_ex_done; 
    
/* regnum is the source */  
#define FP_EX_OPA_SAVE_V(regnum)                                                \
        R3_FROM_STACK (regnum);                                                 \
        swi     r3, r0, mb_fpex_op_a;                                           \
        bri     handle_fp_ex_done; 

#define FP_EX_UNHANDLED                                                         \
        bri     fp_ex_unhandled;                                                \
        nop;                                                                    \
        nop;

/* Extern declarations */
.extern MB_ExceptionVectorTable


#ifdef MICROBLAZE_EXCEPTIONS_ENABLED                    /* If exceptions are enabled in the processor */
                
/* 
 * hw_exception_handler - Handler for unaligned exceptions
 * Exception handler notes:     
 * - Does not handle exceptions other than unaligned exceptions
 * - Does not handle exceptions during load into r17, r1, r0.
 * - Does not handle exceptions during store from r17 (cannot be done) and r1 (slows down common case)
 *
 *  Relevant register structures
 *        
 *  EAR - |----|----|----|----|----|----|----|----|      
 *      - <  ##   32 bit faulting address     ##  >      
 *       
 *  ESR - |----|----|----|----|----| - | - |-----|-----| 
 *      -                            W   S   REG   EXC
 *
 *        
 * STACK FRAME STRUCTURE
 * ---------------------
 *
 *      +-------------+         + 0
 *      |     MSR     |
 *      +-------------+         + 4                
 *      |     r1      |
 *      |      .      |
 *      |      .      |
 *      |      .      |
 *      |      .      |
 *      |     r18     |
 *      +-------------+         + 76
 *      |      .      |
 *      |      .      |        
 */        

         
.global _hw_exception_handler                               
.section .text                                          
.align 2
.ent _hw_exception_handler
_hw_exception_handler:                      
        addik   r1, r1, -(EX_HANDLER_STACK_SIZ);        /* Create stack frame */
        PUSH_REG(3);              
        PUSH_REG(4);              
        PUSH_REG(5);              
        PUSH_REG(6);
        PUSH_REG(17);
        PUSH_MSR_AND_ENABLE_EXC;                        /* Exceptions enabled here. This will allow nested exceptions */
                
        mfs     r3, resr;    
        andi    r5, r3, 0x1F;                           /* Extract ESR[EXC]                     */

#if (! defined (NO_UNALIGNED_EXCEPTIONS) && ! defined (USER_SPEC_UNALIGNED_HANDLER))
        xori    r6, r5, 1;                              /* 00001 = Unaligned Exception          */
        beqi    r6, handle_unaligned_ex ;               /* Jump to unalignment exception handler*/
#endif  /* (! defined (NO_UNALIGNED_EXCEPTIONS) && ! defined (USER_SPEC_UNALIGNED_HANDLER)) */

#if defined (MICROBLAZE_FP_EXCEPTION_ENABLED) && defined (MICROBLAZE_FP_EXCEPTION_DECODE)
        xori   r6, r5, 6;                               /* 00110 = FPU exception */
        beqi   r6, handle_fp_ex;                        /* Go and decode the FP exception */
#endif  /* defined (MICROBLAZE_FP_EXCEPTION_ENABLED) && defined (MICROBLAZE_FP_EXCEPTION_DECODE) */

#if (! defined (NO_OTHER_EXCEPTIONS) || (defined(USER_SPEC_UNALIGNED_HANDLER)))
handle_other_ex:                                        /* Handle Other exceptions here         */        
        ori     r6, r0, 7; 
        cmp     r6, r5, r6;                             /* >= 7 are unknown exceptions. Do not handle these */
        blei    r6, ex_handler_done;

handle_other_ex_tail:       
        PUSH_REG(7);                                    /* Save other volatiles before we make procedure calls below   */
        PUSH_REG(8);             
        PUSH_REG(9);              
        PUSH_REG(10);             
        PUSH_REG(11);             
        PUSH_REG(12);
        PUSH_REG(15);
        PUSH_REG(18);        

        la      r4, r0, MB_ExceptionVectorTable;        /* Load the Exception vector table base address         */
        addik   r5, r5, -1                              /* Interesting exception numbers start range from 1-6. 
                                                           Convert to array index. */        
        addk    r7, r5, r5;                             /* Calculate exception vector offset = r5 * 8           */
        addk    r7, r7, r7;         
        addk    r7, r7, r7;
        addk    r7, r7, r4;                             /* Get pointer to exception vector               */
        lwi     r5, r7, 4;                              /* Load argument to exception handler from table */
        lw      r7, r7, r0;                             /* Load vector itself here                       */

        brald   r15, r7;                                /* Branch to handler                             */
        nop;
        
        POP_REG(7);                                     /* Restore other volatiles */
        POP_REG(8);              
        POP_REG(9);               
        POP_REG(10);              
        POP_REG(11);              
        POP_REG(12);
        POP_REG(15);
        POP_REG(18);        
#endif /* (! defined (NO_OTHER_EXCEPTIONS) || (defined(USER_SPEC_UNALIGNED_HANDLER))) */

#if (! defined (NO_UNALIGNED_EXCEPTIONS) && ! defined (USER_SPEC_UNALIGNED_HANDLER))
        bri     ex_handler_done;                        /* Complete exception handling       */        
handle_unaligned_ex:    
        andi    r6, r3, 0x3E0;                          /* Mask and extract the register operand */
        srl     r6, r6;                                 /* r6 >> 5 */
        srl     r6, r6;
        srl     r6, r6;
        srl     r6, r6;
        srl     r6, r6;
        sbi     r6, r0, ex_reg_op;                      /* Store the register operand in a temporary location */
        mfs     r4, rear;                              
        andi    r6, r3, 0x400;                          /* Extract ESR[S]               */
        bnei    r6, ex_sw;
ex_lw:  
        andi    r6, r3, 0x800;                          /* Extract ESR[W]               */
        beqi    r6, ex_lhw;
        lbui    r5, r4, 0;                              /* Exception address in r4      */
        sbi     r5, r0, ex_tmp_data_loc_0;              /* Load a word, byte-by-byte from destination address and save it in tmp space  */              
        lbui    r5, r4, 1;
        sbi     r5, r0, ex_tmp_data_loc_1;
        lbui    r5, r4, 2;
        sbi     r5, r0, ex_tmp_data_loc_2;
        lbui    r5, r4, 3;
        sbi     r5, r0, ex_tmp_data_loc_3;
        lwi     r3, r0, ex_tmp_data_loc_0;              /* Get the destination register value into r3   */
        bri     ex_lw_tail;      
ex_lhw: 
        lbui    r5, r4, 0;                              /* Exception address in r4                      */
        sbi     r5, r0, ex_tmp_data_loc_0;              /* Load a half-word, byte-by-byte from destination address and save it in tmp space */  
        lbui    r5, r4, 1;                               
        sbi     r5, r0, ex_tmp_data_loc_1;
        lhui    r3, r0, ex_tmp_data_loc_0;              /* Get the destination register value into r3   */
ex_lw_tail:
        lbui    r5, r0, ex_reg_op;                      /* Get the destination register number into r5  */
        la      r6, r0, lw_table;                       /* Form load_word jump table offset (lw_table + (8 * regnum)) */
        addk    r5, r5, r5;                              
        addk    r5, r5, r5;
        addk    r5, r5, r5;
        addk    r5, r5, r6;
        bra     r5;
ex_lw_end:                                              /* Exception handling of load word, ends */
ex_sw:          
        lbui    r5, r0, ex_reg_op;                      /* Get the destination register number into r5 */
        la      r6, r0, sw_table;                       /* Form store_word jump table offset (sw_table + (8 * regnum)) */
        add     r5, r5, r5;                             
        add     r5, r5, r5;
        add     r5, r5, r5;
        add     r5, r5, r6;
        bra     r5;
ex_sw_tail:             
        mfs     r6, resr;                               
        andi    r6, r6, 0x800;                          /* Extract ESR[W]       */
        beqi    r6, ex_shw;
        swi     r3, r0, ex_tmp_data_loc_0;
        lbui    r3, r0, ex_tmp_data_loc_0;              /* Store the word, byte-by-byte into destination address                */
        sbi     r3, r4, 0;
        lbui    r3, r0, ex_tmp_data_loc_1;
        sbi     r3, r4, 1;
        lbui    r3, r0, ex_tmp_data_loc_2;
        sbi     r3, r4, 2;       
        lbui    r3, r0, ex_tmp_data_loc_3;
        sbi     r3, r4, 3;                      
        bri     ex_handler_done;
ex_shw:         
        swi     r3, r0, ex_tmp_data_loc_0;              /* Store the lower half-word, byte-by-byte into destination address      */
        lbui    r3, r0, ex_tmp_data_loc_2;
        sbi     r3, r4, 0;
        lbui    r3, r0, ex_tmp_data_loc_3;
        sbi     r3, r4, 1;
ex_sw_end:                                              /* Exception handling of store word, ends. */
        bri     ex_handler_done; 
#endif  /* (! defined (NO_UNALIGNED_EXCEPTIONS) && ! defined (USER_SPEC_UNALIGNED_HANDLER)) */

#if defined (MICROBLAZE_FP_EXCEPTION_ENABLED) && defined (MICROBLAZE_FP_EXCEPTION_DECODE)
handle_fp_ex:
        addik   r3, r17, -4;                            /* r17 contains (addr of exception causing FP instruction + 4) */
        lw      r4, r0, r3;                             /* We might find ourselves in a spot here. Unguaranteed load   */

handle_fp_ex_opb:
        la      r6, r0, fp_table_opb;                   /* Decode opB and store its value in mb_fpex_op_b */
        srl     r4, r4; 
        srl     r4, r4; 
        srl     r4, r4; 
        srl     r4, r4; 
        srl     r4, r4; 
        srl     r4, r4; 
        srl     r4, r4; 
        srl     r4, r4; 
        srl     r4, r4; 
        srl     r4, r4; 
        srl     r4, r4; 
        andi    r3, r4, 0x1F;
        add     r3, r3, r3;                             /* Calculate (fp_table_opb + (regno * 12)) in r5 */
        add     r3, r3, r3;
        add     r5, r3, r3;
        add     r5, r5, r3;
        add     r5, r5, r6;
        bra     r5; 

handle_fp_ex_opa:
        la      r6, r0, fp_table_opa;                   /* Decode opA and store its value in mb_fpex_op_a */
        srl     r4, r4; 
        srl     r4, r4; 
        srl     r4, r4; 
        srl     r4, r4; 
        srl     r4, r4; 
        andi    r3, r4, 0x1F;
        add     r3, r3, r3;                             /* Calculate (fp_table_opb + (regno * 12)) in r5 */
        add     r3, r3, r3;
        add     r5, r3, r3;
        add     r5, r5, r3;
        add     r5, r5, r6;
        bra     r5; 

handle_fp_ex_done:
        ori     r5, r0, 6;                              /* Set exception number back to 6 */
        bri     handle_other_ex_tail; 
    
fp_ex_unhandled:    
        bri     0; 
#endif  /* defined (MICROBLAZE_FP_EXCEPTION_ENABLED) && defined (MICROBLAZE_FP_EXCEPTION_DECODE) */
                     
ex_handler_done:
        POP_MSR;
        POP_REG(3);               
        POP_REG(4);               
        POP_REG(5);               
        POP_REG(6); 
        POP_REG(17); 
        rted    r17, 0
        addik   r1, r1, (EX_HANDLER_STACK_SIZ);         /* Restore stack frame  */        
ex_handler_unhandled:   
        bri 0                                           /* UNHANDLED. TRAP HERE */                                                 
.end _hw_exception_handler  

#if (! defined (NO_UNALIGNED_EXCEPTIONS) && ! defined (USER_SPEC_UNALIGNED_HANDLER))        

/* 
 * hw_exception_handler Jump Table
 * - Contains code snippets for each register that caused the unaligned exception.
 * - Hence exception handler is NOT self-modifying
 * - Separate table for load exceptions and store exceptions.
 * - Each table is of size:   (8 * 32) = 256 bytes
 */
                
.section .text
.align  4
lw_table:
lw_r0:  R3_TO_LWREG   (0); 
lw_r1:  LWREG_NOP;
lw_r2:  R3_TO_LWREG   (2);
lw_r3:  R3_TO_LWREG_V (3);
lw_r4:  R3_TO_LWREG_V (4);
lw_r5:  R3_TO_LWREG_V (5);
lw_r6:  R3_TO_LWREG_V (6);
lw_r7:  R3_TO_LWREG   (7);
lw_r8:  R3_TO_LWREG   (8);
lw_r9:  R3_TO_LWREG   (9);
lw_r10: R3_TO_LWREG   (10);
lw_r11: R3_TO_LWREG   (11);                             
lw_r12: R3_TO_LWREG   (12);
lw_r13: R3_TO_LWREG   (13);
lw_r14: R3_TO_LWREG   (14);                                                     
lw_r15: R3_TO_LWREG   (15);                                                     
lw_r16: R3_TO_LWREG   (16);                                                     
lw_r17: LWREG_NOP;
lw_r18: R3_TO_LWREG   (18);                                                     
lw_r19: R3_TO_LWREG   (19);                                                     
lw_r20: R3_TO_LWREG   (20);                                                     
lw_r21: R3_TO_LWREG   (21);
lw_r22: R3_TO_LWREG   (22);
lw_r23: R3_TO_LWREG   (23);                                                     
lw_r24: R3_TO_LWREG   (24);                                                     
lw_r25: R3_TO_LWREG   (25);                                                     
lw_r26: R3_TO_LWREG   (26);                                                     
lw_r27: R3_TO_LWREG   (27);                                                     
lw_r28: R3_TO_LWREG   (28);                                                     
lw_r29: R3_TO_LWREG   (29);                                                     
lw_r30: R3_TO_LWREG   (30);
lw_r31: R3_TO_LWREG   (31);

sw_table:
sw_r0:  SWREG_TO_R3   (0); 
sw_r1:  SWREG_NOP;
sw_r2:  SWREG_TO_R3   (2);
sw_r3:  SWREG_TO_R3_V (3);
sw_r4:  SWREG_TO_R3_V (4);
sw_r5:  SWREG_TO_R3_V (5);
sw_r6:  SWREG_TO_R3_V (6);
sw_r7:  SWREG_TO_R3   (7);
sw_r8:  SWREG_TO_R3   (8);
sw_r9:  SWREG_TO_R3   (9);
sw_r10: SWREG_TO_R3   (10);
sw_r11: SWREG_TO_R3   (11);                             
sw_r12: SWREG_TO_R3   (12);
sw_r13: SWREG_TO_R3   (13);
sw_r14: SWREG_TO_R3   (14);                                                     
sw_r15: SWREG_TO_R3   (15);                                                     
sw_r16: SWREG_TO_R3   (16);                                                     
sw_r17: SWREG_NOP; 
sw_r18: SWREG_TO_R3   (18);                                                     
sw_r19: SWREG_TO_R3   (19);                                                     
sw_r20: SWREG_TO_R3   (20);                                                     
sw_r21: SWREG_TO_R3   (21);
sw_r22: SWREG_TO_R3   (22);
sw_r23: SWREG_TO_R3   (23);                                                     
sw_r24: SWREG_TO_R3   (24);                                                     
sw_r25: SWREG_TO_R3   (25);                                                     
sw_r26: SWREG_TO_R3   (26);                                                     
sw_r27: SWREG_TO_R3   (27);                                                     
sw_r28: SWREG_TO_R3   (28);                                                     
sw_r29: SWREG_TO_R3   (29);                                                     
sw_r30: SWREG_TO_R3   (30);
sw_r31: SWREG_TO_R3   (31);

/* Temporary data structures used in the handler */
.section .data
.align 2
ex_tmp_data_loc_0:      
        .byte 0
ex_tmp_data_loc_1:      
        .byte 0
ex_tmp_data_loc_2:      
        .byte 0
ex_tmp_data_loc_3:      
        .byte 0                 
ex_reg_op:
        .byte 0
    
#endif /* (! defined (NO_UNALIGNED_EXCEPTIONS) && ! defined (USER_SPEC_UNALIGNED_HANDLER)) */
    
#if defined (MICROBLAZE_FP_EXCEPTION_ENABLED) && defined (MICROBLAZE_FP_EXCEPTION_DECODE)
/* 
 * FP exception decode jump table.
 * - Contains code snippets for each register that could have been a source operand for an excepting FP instruction
 * - Hence exception handler is NOT self-modifying
 * - Separate table for opA and opB
 * - Each table is of size:   (12 * 32) = 384 bytes
 */
    
.section .text
.align  4
fp_table_opa:
opa_r0: FP_EX_OPA_SAVE (0); 
opa_r1: FP_EX_UNHANDLED; 
opa_r2: FP_EX_OPA_SAVE (2);     
opa_r3: FP_EX_OPA_SAVE_V (3);     
opa_r4: FP_EX_OPA_SAVE_V (4);     
opa_r5: FP_EX_OPA_SAVE_V (5);     
opa_r6: FP_EX_OPA_SAVE_V (6);     
opa_r7: FP_EX_OPA_SAVE (7);     
opa_r8: FP_EX_OPA_SAVE (8);     
opa_r9: FP_EX_OPA_SAVE (9);     
opa_r10: FP_EX_OPA_SAVE (10);     
opa_r11: FP_EX_OPA_SAVE (11);     
opa_r12: FP_EX_OPA_SAVE (12);     
opa_r13: FP_EX_OPA_SAVE (13);     
opa_r14: FP_EX_UNHANDLED; 
opa_r15: FP_EX_UNHANDLED; 
opa_r16: FP_EX_UNHANDLED; 
opa_r17: FP_EX_UNHANDLED; 
opa_r18: FP_EX_OPA_SAVE (18);     
opa_r19: FP_EX_OPA_SAVE (19);     
opa_r20: FP_EX_OPA_SAVE (20);     
opa_r21: FP_EX_OPA_SAVE (21);     
opa_r22: FP_EX_OPA_SAVE (22);     
opa_r23: FP_EX_OPA_SAVE (23);     
opa_r24: FP_EX_OPA_SAVE (24);     
opa_r25: FP_EX_OPA_SAVE (25);     
opa_r26: FP_EX_OPA_SAVE (26);     
opa_r27: FP_EX_OPA_SAVE (27);     
opa_r28: FP_EX_OPA_SAVE (28);     
opa_r29: FP_EX_OPA_SAVE (29);     
opa_r30: FP_EX_OPA_SAVE (30);     
opa_r31: FP_EX_OPA_SAVE (31);     

fp_table_opb:   
opb_r0: FP_EX_OPB_SAVE (0); 
opb_r1: FP_EX_UNHANDLED; 
opb_r2: FP_EX_OPB_SAVE (2);     
opb_r3: FP_EX_OPB_SAVE_V (3);     
opb_r4: FP_EX_OPB_SAVE_V (4);     
opb_r5: FP_EX_OPB_SAVE_V (5);     
opb_r6: FP_EX_OPB_SAVE_V (6);     
opb_r7: FP_EX_OPB_SAVE (7);     
opb_r8: FP_EX_OPB_SAVE (8);     
opb_r9: FP_EX_OPB_SAVE (9);     
opb_r10: FP_EX_OPB_SAVE (10);     
opb_r11: FP_EX_OPB_SAVE (11);     
opb_r12: FP_EX_OPB_SAVE (12);     
opb_r13: FP_EX_OPB_SAVE (13);     
opb_r14: FP_EX_UNHANDLED; 
opb_r15: FP_EX_UNHANDLED; 
opb_r16: FP_EX_UNHANDLED; 
opb_r17: FP_EX_UNHANDLED; 
opb_r18: FP_EX_OPB_SAVE (18);     
opb_r19: FP_EX_OPB_SAVE (19);     
opb_r20: FP_EX_OPB_SAVE (20);     
opb_r21: FP_EX_OPB_SAVE (21);     
opb_r22: FP_EX_OPB_SAVE (22);     
opb_r23: FP_EX_OPB_SAVE (23);     
opb_r24: FP_EX_OPB_SAVE (24);     
opb_r25: FP_EX_OPB_SAVE (25);     
opb_r26: FP_EX_OPB_SAVE (26);     
opb_r27: FP_EX_OPB_SAVE (27);     
opb_r28: FP_EX_OPB_SAVE (28);     
opb_r29: FP_EX_OPB_SAVE (29);     
opb_r30: FP_EX_OPB_SAVE (30);     
opb_r31: FP_EX_OPB_SAVE (31);     
    
#endif  /* defined (MICROBLAZE_FP_EXCEPTION_ENABLED) && defined (MICROBLAZE_FP_EXCEPTION_DECODE) */
    
#if defined(MICROBLAZE_FP_EXCEPTION_ENABLED) && defined(MICROBLAZE_FP_EXCEPTION_DECODE)
/* This is where we store the opA and opB of the last excepting FP instruction */    
.global mb_fpex_op_a
.global mb_fpex_op_b
.align 2    
mb_fpex_op_a:
        .long 0
mb_fpex_op_b:
        .long 0
#endif /* defined (MICROBLAZE_FP_EXCEPTION_ENABLED) && defined (MICROBLAZE_FP_EXCEPTION_DECODE) */
        
#else                                                   /* Dummy exception handler, in case exceptions are not present in the processor */

.global _hw_exception_handler                               
.section .text                                          
.align 2
.ent _hw_exception_handler
_hw_exception_handler:
        bri     0; 
.end _hw_exception_handler        
                                
#endif  /* MICROBLAZE_EXCEPTIONS_ENABLED */



