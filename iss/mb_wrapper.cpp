/********************************************************************
 * Copyright (C) 2009, 2012 by Verimag                              *
 * Initial author: Matthieu Moy                                     *
 * Modified by: Mauricio Altieri and João Leidens                   *
 ********************************************************************/

#include "ensitlm.h"
#include "mb_wrapper.h"
#include "microblaze.h"
#include <iomanip>


/* Time between two step()s */
static const sc_core::sc_time PERIOD(20, sc_core::SC_NS);

//#define DEBUG
//#define INFO

using namespace std;

MBWrapper::MBWrapper(sc_core::sc_module_name name)
        : sc_core::sc_module(name), irq("irq"),
          m_iss(0) /* identifier, not very usefull since we have only one instance */
{
        m_iss.reset();
        m_iss.setIrq(false);
        irq_actived = false;
        SC_THREAD(run_iss);
        
        SC_METHOD(irq_handler);
        sensitive << irq.pos();
}

void MBWrapper::exec_data_request(enum iss_t::DataAccessType mem_type,
                                  uint32_t mem_addr,
                                  uint32_t mem_wdata) {
        uint32_t localbuf;
        uint32_t byte_offset;
        
        tlm::tlm_response_status status;
        switch (mem_type) {
        case iss_t::READ_WORD:
        {
                /* The ISS requested a word read
                 * (mem_addr into localbuf). 
                 */
                status = socket.read(mem_addr, localbuf);
                if (status != tlm::TLM_OK_RESPONSE) { 
                        std::cerr << "Read error at address " << hex << mem_addr << std::endl
                                  << "Response status " << status << std::endl;                      
                }
#ifdef DEBUG
                std::cout << hex << "read    " << setw(10) << localbuf << " at address " << mem_addr << std::endl;
#endif
                /* Converting the data from little-endian (Intel) to big-endian (ISS) */
                localbuf = uint32_machine_to_be(localbuf);
                m_iss.setDataResponse(0,localbuf);
        }
        break;
        case iss_t::READ_BYTE:
                /* The ISS requested a byte read
                 * (mem_addr into localbuf).
                 *
                 * Since the bus only works with addresses that are multiples of 4
                 * the read must be performed on the word containing this byte
                 */
                byte_offset = mem_addr % sizeof(uint32_t);
                status = socket.read(mem_addr - byte_offset, localbuf);
                if (status != tlm::TLM_OK_RESPONSE) { 
                        std::cerr << "Read error at address " << hex << mem_addr - byte_offset << std::endl
                                  << "Response status " << status << std::endl;                      
                }
#ifdef DEBUG
                std::cout << hex << "read    " << setw(10) << localbuf << " at address " << mem_addr << std::endl;
#endif

                /* Converting the data from little-endian to big-endian
                 * while keeping only the requested byte
                 */
                localbuf >>= 8 * ((sizeof(uint32_t) - 1) - byte_offset);
                localbuf &= 0xFF;                        

                m_iss.setDataResponse(0,localbuf);
                break;
            
        case iss_t::WRITE_HALF:    
        case iss_t::READ_HALF:
                /* Not needed for our platform. */
                std::cerr << "Operation " << mem_type
                          << " unsupported for " << std::showbase << std::hex << mem_addr
                          << std::endl;
                abort();
        case iss_t::LINE_INVAL:
                /* No cache => nothing to do. */
                break;
                
        case iss_t::WRITE_BYTE:
        case iss_t::WRITE_WORD:
        {
                /* The ISS requested a data write
                 * (mem_wdata at mem_addr). 
                 *
                 * Firstly the data must be converted
                 * from big-endian to little-endian.
                 */
                localbuf = uint32_be_to_machine(mem_wdata);
                status = socket.write(mem_addr, localbuf);
                if (status != tlm::TLM_OK_RESPONSE) { 
                        std::cerr << "Write error at address " << hex << mem_addr << std::endl
                                  << "Response status " << status << std::endl;                      
                }
#ifdef DEBUG
                std::cout << hex << "wrote   " << setw(10) << localbuf << " at address " << mem_addr << std::endl;
#endif
                m_iss.setDataResponse(0,0);
        }
        break;
        case iss_t::STORE_COND:
                break;
        case iss_t::READ_LINKED:
                break;
        }
}

void MBWrapper::run_iss(void) {

        uint32_t localbuf;
        int inst_count = 0;

        while(true) {
#ifdef DEBUG
                std::cout << "Starting new processor cycle" << std::endl;
#endif
                if (m_iss.isBusy())
                        m_iss.nullStep();
                else {
                        bool ins_asked;
                        uint32_t ins_addr;
                        m_iss.getInstructionRequest(ins_asked, ins_addr);

                        if (ins_asked) {
                                /* The ISS requested an instruction.
                                 * We have to do the instruction fetch
                                 * by reading from memory, 
                                 * and converting it to big-endian.
                                 */
                                socket.read(ins_addr, localbuf);
                                if (status != tlm::TLM_OK_RESPONSE) { 
                                        std::cerr << "Read error at address " 
                                                  << hex << ins_addr << std::endl
                                                  << "Response status " << status 
                                                  << std::endl;                      
                                }
                                localbuf = uint32_machine_to_be(localbuf);
                                m_iss.setInstruction(0, localbuf);
                        }

                        bool mem_asked;
                        enum iss_t::DataAccessType mem_type;
                        uint32_t mem_addr;
                        uint32_t mem_wdata;
                        m_iss.getDataRequest( mem_asked, mem_type, mem_addr, mem_wdata );

                        if (mem_asked) {
                                exec_data_request(mem_type, mem_addr, mem_wdata);
                        }
                        m_iss.step();
                        
                        /* Hold on for 5 steps before resetting the IRQ,
                         * while the ISS will treat the interruption. 
                         */
                        if (irq_actived){
                                inst_count++;
                                if (inst_count == 5){
                                        m_iss.setIrq(false);
                                        irq_actived = false;
                                        inst_count = 0;
                                }
                        }
                }
                sc_core::wait(PERIOD);
        }
}

void MBWrapper::irq_handler(void) {
        m_iss.setIrq(true);
        irq_actived = true;
}
