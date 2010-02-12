--  GECKO3COM IP Core
--
--  Copyright (C) 2010 by
--   ___    ___   _   _
--  (  _ \ (  __)( ) ( )
--  | (_) )| (   | |_| |   Bern University of Applied Sciences
--  |  _ < |  _) |  _  |   School of Engineering and
--  | (_) )| |   | | | |   Information Technology
--  (____/ (_)   (_) (_)
--
--  This program is free software: you can redistribute it and/or modify
--  it under the terms of the GNU General Public License as published by
--  the Free Software Foundation, either version 3 of the License, or
--  (at your option) any later version.
--
--  This program is distributed in the hope that it will be useful,
--  but WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--  GNU General Public License for more details. 
--  You should have received a copy of the GNU General Public License
--  along with this program.  If not, see <http://www.gnu.org/licenses/>.
--
--  URL to the project description: 
--    http://labs.ti.bfh.ch/gecko/wiki/systems/gecko3com/start
--------------------------------------------------------------------------------
--
--  Author:  Andreas Habegger, Christoph Zimmermann
--  Date of creation: 11. February 2010
--  Description:
--      Test scenario for the GECKO3com simple IP core.
--   	(Not the one for Xilinx EDK)
--	This test module has two operation mode (selectable by external switch):
--      - Send back a response message stored in rom
--      - Send back a stream of pseudo random data. Size is defined as a constant
--
--  Target Devices:	general
--  Tool versions: 	11.1
--  Dependencies:
--
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.GECKO3COM_defines.all;

entity GECKO3COM_simple_test is
  port (
    i_nReset      : in    std_logic;
    i_sysclk      : in    std_logic;    -- FPGA System CLK
    -- Interface signals to the EZ-USB FX2
    i_IFCLK       : in    std_logic;    -- GPIF CLK
    i_WRU         : in    std_logic;    -- write from GPIF
    i_RDYU        : in    std_logic;    -- GPIF is ready
    o_WRX         : out   std_logic;    -- To write to GPIF
    o_RDYX        : out   std_logic;    -- IP Core is ready
    -- bidirect data bus
    b_gpif_bus    : inout std_logic_vector(SIZE_DBUS_GPIF-1 downto 0)
    -- simple test "user interface" signals
    o_LEDrx       : out   std_logic;    -- controll LED receive data
    o_LEDtx       : out   std_logic;    -- controll LED send data
    o_LEDrun      : out   std_logic;    -- power LED
    i_mode_switch : in    std_logic_vector(2 downto 0));
end GECKO3COM_simple_test;



architecture behavour of GECKO3COM_simple_test is

  ----------------------------------------------------------------------------- 
  --     CONSTANTS  
  -----------------------------------------------------------------------------
  constant BUSWIDTH : integer := 32; -- you can choose here 32 or 16

  -- lenght of the message stored in the response message rom:
  constant c_transfer_size_rom : std_logic_vector(31 downto 0) := x"0000000E";

  -- we will transmitt 1 MiB data when the pseude random number generator
  -- is used:
  constant c_transfer_size_prng : std_logic_vector(31 downto 0) := x"00100000";

  
  ----------------------------------------------------------------------------- 
  --     COMPONENTS  
  -----------------------------------------------------------------------------
  component GECKO3COM_simple
    generic (
      BUSWIDTH : integer);
    port (
      i_nReset                 : in    std_logic;
      i_sysclk                 : in    std_logic;
      i_receive_fifo_rd_en     : in    std_logic;
      o_receive_fifo_empty     : out   std_logic;
      o_receive_fifo_data      : out   std_logic_vector(BUSWIDTH-1 downto 0);
      o_receive_transfersize   : out   std_logic_vector(31 downto 0);
      o_receive_end_of_message : out   std_logic;
      o_receive_newdata        : out   std_logic;
      i_send_fifo_wr_en        : in    std_logic;
      o_send_fifo_full         : out   std_logic;
      i_send_fifo_data         : in    std_logic_vector(BUSWIDTH-1 downto 0);
      i_send_transfersize      : in    std_logic_vector(31 downto 0);
      i_send_transfersize_en   : in    std_logic;
      i_send_have_more_data    : in    std_logic;
      o_send_data_request      : out   std_logic;
      o_send_finished          : out   std_logic;
      o_rx                     : out   std_logic;
      o_tx                     : out   std_logic;
      i_IFCLK                  : in    std_logic;
      i_WRU                    : in    std_logic;
      i_RDYU                   : in    std_logic;
      o_WRX                    : out   std_logic;
      o_RDYX                   : out   std_logic;
      b_gpif_bus               : inout std_logic_vector(SIZE_DBUS_GPIF-1 downto 0));
  end component;


  component response_message_rom
    port (
      A : in  std_logic_vector(3 downto 0);
      D : out std_logic_vector(31 downto 0));
  end component;
  
  -----------------------------------------------------------------------------
  -- interconection signals
  -----------------------------------------------------------------------------

  signal s_receive_fifo_rd_en     : std_logic;
  signal s_receive_fifo_empty     : std_logic;
  signal s_receive_fifo_data      : std_logic_vector(BUSWIDTH-1 downto 0);
  signal s_receive_transfersize   : std_logic_vector(31 downto 0);
  signal s_receive_end_of_message : std_logic;
  signal s_receive_newdata        : std_logic;
  signal s_send_fifo_wr_en        : std_logic;
  signal s_send_fifo_full         : std_logic;
  signal s_send_fifo_data         : std_logic_vector(BUSWIDTH-1 downto 0);
  signal s_send_transfersize      : std_logic_vector(31 downto 0);
  signal s_send_transfersize_en   : std_logic;
  signal s_send_have_more_data    : std_logic;
  signal s_send_data_request      : std_logic;
  signal s_send_finished          : std_logic;

  signal s_mode                              : std_logic_vector(1 downto 0);
  signal s_transfer_size_reg_select          : std_logic;
  signal s_transfer_size_reg_en              : std_logic;
  signal s_have_more_data                    : std_logic;
  signal s_send_counter_reset                : std_logic;
  signal s_send_counter_en                   : std_logic;
  signal s_send_counter_equals_transfer_size : std_logic;
  signal s_prng_en                           : std_logic;
  signal s_prng_feedback                     : std_logic;
  signal s_receive_data_error                : std_logic;

  signal s_receive_data_old        : std_logic_vector(31 downto 0);
  signal s_selected_transfer_size  : std_logic_vector(31 downto 0);
  signal s_remaining_transfer_size : std_logic_vector(31 downto 0);
  signal s_send_counter_value      : std_logic_vector(31 downto 0);
  signal s_prng_data               : std_logic_vector(31 downto 0);
  signal s_message_rom_data        : std_logic_vector(31 downto 0);


  -----------------------------------------------------------------------------
  -- finite state machine signals
  -----------------------------------------------------------------------------
    -- XST specific synthesize attributes
  attribute safe_implementation: string;
  attribute safe_recovery_state: string;
  
  type t_fsmState is (st1_idle, st2_get_data, st3_load_total_transfer_size,
                      st4_save_remaining_transfer_size, st5_send_data,
                      st6_send_wait, st7_subtract_transfered_data,
                      st8_reset_send_counter);
  
  signal state, next_state : t_fsmState;
  
  -- XST specific synthesize attributes
  attribute safe_recovery_state of pr_state : signal is "idle";
  attribute safe_implementation of pr_state : signal is "yes";

  

begin --  behavour

  GECKO3COM_simple_1: GECKO3COM_simple
    generic map (
      BUSWIDTH => BUSWIDTH)
    port map (
      i_nReset                 => i_nReset,
      i_sysclk                 => i_sysclk,
      i_receive_fifo_rd_en     => s_receive_fifo_rd_en,
      o_receive_fifo_empty     => s_receive_fifo_empty,
      o_receive_fifo_data      => s_receive_fifo_data,
      o_receive_transfersize   => s_receive_transfersize,
      o_receive_end_of_message => s_receive_end_of_message,
      o_receive_newdata        => s_receive_newdata,
      i_send_fifo_wr_en        => s_send_fifo_wr_en,
      o_send_fifo_full         => s_send_fifo_full,
      i_send_fifo_data         => s_send_fifo_data,
      i_send_transfersize      => s_send_transfersize,
      i_send_transfersize_en   => s_send_transfersize_en,
      i_send_have_more_data    => s_send_have_more_data,
      o_send_data_request      => s_send_data_request,
      o_send_finished          => s_send_finished,
      o_rx                     => o_LEDrx,
      o_tx                     => o_LEDtx,
      i_IFCLK                  => i_IFCLK,
      i_WRU                    => i_WRU,
      i_RDYU                   => i_RDYU,
      o_WRX                    => o_WRX,
      o_RDYX                   => o_RDYX,
      b_gpif_bus               => b_gpif_bus);


  response_message_rom_1: response_message_rom
    port map (
      A => s_send_counter_value(3 downto 0),
      D => s_message_rom_data);

  
  o_LEDrun <= '1';


  -- purpose: converts the mode_switch input to a binary coded value
  -- type   : combinational
  -- inputs : i_mode_switch
  -- outputs: s_mode
  mode_switch_decoder: process (i_mode_switch)
  begin  -- process mode_switch_decoder
    if i_mode_switch = "xx1" then
      s_mode <= "00";
    elsif i_mode_switch = "x1x" then
      s_mode <= "01";
    elsif i_mode_switch = "1xx" then
      s_mode <= "10";
    else
      s_mode <= "00";
    end if;
  end process mode_switch_decoder;


  -----------------------------------------------------------------------------
  -- components needed in the send path
  -----------------------------------------------------------------------------
  
  -- purpose: mulitiplexer to select the send data source
  -- type   : combinational
  -- inputs : s_mode, s_prng_data, s_message_rom_data
  -- outputs: s_send_fifo_data
  send_data_mux: process (s_mode, s_prng_data, s_message_rom_data)
  begin  -- process send_data_mux
    case i_send_mux_sel is
      when "00" => s_send_fifo_data <= s_message_rom_data;
      when "01" => s_send_fifo_data <= s_prng_data;
      when others => s_send_fifo_data <= (others => 'x')
    end case;
  end process send_data_mux;

  
  -- purpose: mulitiplexer to select the send transfer size
  -- type   : combinational
  -- inputs : s_mode, c_transfer_size_rom, c_transfer_size_prng
  -- outputs: s_selected_transfer_size
  send_transfersize_mode_mux: process (s_mode, c_transfer_size_rom, c_transfer_size_prng)
  begin  -- process send_transfersize_mode_mux
    case s_mode is
      when "00" => s_selected_transfer_size <= c_transfer_size_rom;
      when "01" => s_selected_transfer_size <= c_transfer_size_prng;
      when others => s_selected_transfer_size <= (others => 'x')
    end case;
  end process send_transfersize_mode_mux;


  -- purpose: stores the initial or remaining transfer size
  -- type   : sequential
  -- inputs : i_sysclk, i_nReset, s_transfer_size_reg_en, s_transfer_size_reg_select,
  --          s_subtract_value
  -- outputs: s_remaining_transfer_size
  remaining_transfer_size_reg: process (i_sysclk, i_nReset)
  begin  -- process current_transfer_size_reg
    if i_nReset = '0' then              -- asynchronous reset (active low)
      s_remaining_transfer_size <= (others => '0');
    elsif i_sysclk'event and i_sysclk = '1' then  -- rising clock edge
      if s_transfer_size_reg_en = '1' then
        if s_transfer_size_reg_select = '1' then
          s_remaining_transfer_size <= s_selected_transfer_size;
        else
          s_remaining_transfer_size <= s_subtract_value;
        end if;
      end if;
    end if;
  end process remaining_transfer_size_reg;

  
  -- purpose: mulitiplexer to select the final transfer size for the selected mode
  -- type   : combinational
  -- inputs : s_mode, c_transfer_size_rom, c_transfer_size_prng
  -- outputs: s_selected_transfer_size
  send_transfersize_mode_mux: process (s_mode, c_transfer_size_rom, c_transfer_size_prng)
  begin  -- process send_transfersize_mode_mux
    case s_mode is
      when "00" => s_selected_transfer_size <= c_transfer_size_rom;
      when "01" => s_selected_transfer_size <= c_transfer_size_prng;
      when others => s_selected_transfer_size <= (others => 'x')
    end case;
  end process send_transfersize_mode_mux;  

 
  -- maximum alowed transfer size comparator
  s_have_more_data <=
    '1' when s_remaining_transfer_size > s_receive_transfersize else
    '0';

  
  -- purpose: mulitiplexer to select the send transfer size
  -- type   : combinational
  -- inputs : s_have_more_data, s_remaining_transfer_size,
  --          s_receive_transfersize
  -- outputs: s_send_transfersize
  send_transfersize_mux: process (s_have_more_data, s_current_transfer_size,
                                  s_receive_transfersize)
  begin  -- process send_transfersize_mux
    case i_send_mux_sel is
      when '0' => s_send_transfersize <= s_remaining_transfer_size;
      when '1' => s_send_transfersize <= s_receive_transfersize
    end case;
  end process send_transfersize_mux;

  
  -- purpose: up counter for the send transfer size
  -- type   : sequential
  -- inputs : i_sysclk, i_nReset, s_send_counter_en, s_send_counter_reset
  --          
  -- outputs: s_send_counter_value
  send_counter : process (i_sysclk, i_nReset)
  begin  -- process send_counter
    if i_nReset = '0' then              -- asynchronous reset (active low)
      s_send_counter_value <= (others => '0');
    elsif i_sysclk'event and i_sysclk = '1' then  -- rising clock edge
      if i_send_counter_reset = '1' then
        s_send_counter_value <= (others => '0');
      end if;
      if i_send_counter_en = '1' then
        s_send_counter_value <= s_send_counter_value + 1;
      end if;
    end if;
  end process send_counter;
  
  -- transfer size counter comparator
  s_send_counter_equals_transfer_size <=
    '1' when s_send_counter_value = s_send_transfersize else
    '0';


  -- purpose: subracts the send counter end value from the remaining transfer size value
  -- type   : combinational
  -- inputs : s_remaining_transfer_size, s_send_counter_value
  -- outputs: s_subtract_value
  transfer_size_subract: process (s_remaining_transfer_size, s_send_counter_value)
  begin  -- process transfer_size_subract
    s_subtract_value <= s_remaining_transfer_size - s_send_counter_value;
  end process transfer_size_subract;


  
  -----------------------------------------------------------------------------
  -- components needed in the receive path
  -----------------------------------------------------------------------------
  
  -- purpose: saves the previous received data word
  -- type   : sequential
  -- inputs : i_sysclk, i_nReset, s_receive_fifo_data, s_receive_fifo_rd_en
  -- outputs: s_receive_fifo_data_old
  receive_fifo_data_reg: process (i_sysclk, i_nReset)
  begin  -- process receive_fifo_data_reg
    if i_nReset = '0' then              -- asynchronous reset (active low)
      s_receive_fifo_data_old <= (others => '0');
    elsif i_sysclk'event and i_sysclk = '1' then  -- rising clock edge
      if s_receive_fifo_rd_en = '1' then
        s_receive_fifo_data_old <= s_receive_fifo_data;
      end if;
    end if;
  end process receive_fifo_data_reg;

  
  -- receive data comparator
  -- (use together with test data with incrementing values)
  s_receive_data_error <=
    '0' when s_receive_fifo_data_old + 1 = s_receive_fifo_data else
    '1';


  -- purpose: linear shift register for the pseude random number
  --          generator (PRNG)
  -- type   : sequential
  -- inputs : i_sysclk, i_nReset, s_prng_en, s_prng_feedback
  -- outputs: s_prng_data
  prng_shiftregister: process (i_sysclk, i_nReset)
  begin  -- process prng_shiftregister
    if i_nReset = '0' then              -- asynchronous reset (active low)
      s_prng_data <= "01010101 01010101 01010101 01010101";
    elsif i_sysclk'event and i_sysclk = '1' then  -- rising clock edge
      if s_prng_en = '1' then
        s_prng_data <= s_prng_data(30 downto 0) & s_prng_feedback;
      end if;
    end if;
  end process prng_shiftregister;

  -- purpose: feedback polynom for the pseudo random number generator (PRNG)
  -- inputs : s_prng_data
  -- outputs: s_prng_feedback
  s_prng_feedback <= s_prng_data(15) xor s_prng_data(13) xor s_prng_data(12)
                     xor s_prng_data(10);


  -----------------------------------------------------------------------------
  -- finite state machine (moore)
  -----------------------------------------------------------------------------

  -- state reg
  fsm_state_reg : process(i_sysclk, i_nReset)
  begin
    if i_nReset = '0' then
      state <= st1_idle;
    elsif i_sysclk'event and i_sysclk = '1' then
        state <= next_state;
    end if;
  end process fsm_state_reg;


  -- comb logic
  next_state_decode: process(state, s_receive_fifo_empty, s_send_fifo_full,
                             s_send_data_request)
  begin  -- process next_state_decode

    --declare default state for next_state to avoid latches
    next_state <= state;           --default is to stay in current state
    
    -- default signal values to avoid latches:
    s_receive_fifo_rd_en       <= '0';
    s_send_transfersize_en     <= '0';
    s_send_fifo_wr_en          <= '0';
    s_transfer_size_reg_select <= '0';
    s_transfer_size_reg_en     <= '0';
    s_send_counter_reset       <= '0';
    s_send_counter_en          <= '0';
    s_prng_en                  <= '0';

    case state is
      -- controll

      when st1_idle =>

        if s_receive_fifo_empty = '0' then
          next_state <= st2_get_data;
        elsif s_send_data_request = '1' then
          next_state <= st3_load_total_transfer_size;
        end if;
        
      when st2_get_data =>
        s_receive_fifo_rd_en <= '1';

        if s_receive_fifo_empty = '1' then
          next_state <= st1_idle;
        end if;
        
      when st3_load_total_transfer_size =>
        s_send_counter_reset       <= '1';
        s_transfer_size_reg_en     <= '1';
        s_transfer_size_reg_select <= '1';

        next_state <= st4_save_remaining_transfer_size;
        
      when st4_save_remaining_transfer_size =>
        s_send_transfersize_en <= '1';

        next_state <= st5_send_data;
        
      when st5_send_data =>
        s_send_fifo_wr_en <= '1';
        s_send_counter_en <= '1';
        if s_mode = "01" then
          s_prng_en <= '1';
        end if;

        if s_send_counter_equals_transfer_size = '1' and s_have_more_data = '0' then
          next_state <= st1_idle;
        elsif s_send_counter_equals_transfer_size = '1' and s_have_more_data = '1' then
          next_state <= st7_subtract_transfered_data;
        elsif s_send_fifo_full = '1' then
          next_state <= st6_send_wait;
        end if;

      when st6_send_wait =>

        if s_send_fifo_full = '0' then
          next_state <= st5_send_data;
        end if;

        when st7_subtract_transfered_data
          s_transfer_size_reg_select <= '0';
        s_transfer_size_reg_en <= '1';

        if s_send_data_request = '1' then
          st8_reset_send_counter;
        end if;
        
      when st8_reset_send_counter =>
        s_send_counter_reset <= '1';

        next_state <= st4_save_remaining_transfer_size;
        
      when others =>
        next_state <= st1_idle;
    end case;
    
  end process next_state_decode;

end  behavour;


----------------------------------------------------------------------------- 
--  RESPONSE MESSAGE ROM  
-----------------------------------------------------------------------------
-- This file was generated with hex2rom written by Daniel Wallner

entity response_message_rom is
        port(
                A       : in std_logic_vector(3 downto 0);
                D       : out std_logic_vector(31 downto 0)
        );
end response_message_rom;

architecture rtl of response_message_rom is
        subtype ROM_WORD is std_logic_vector(31 downto 0);
        type ROM_TABLE is array(0 to 3) of ROM_WORD;
        signal ROM: ROM_TABLE := ROM_TABLE'(
                "00100010001000000010110000110000",     -- 0x0000
                "01100101001000000110111101001110",     -- 0x0004
                "01110010011011110111001001110010",     -- 0x0008
                "00001010000010100000101000100010");    -- 0x000C
begin
        D <= ROM(to_integer(unsigned(A)));
end;
