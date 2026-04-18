-- ADC_PERIPHERAL_Revised.vhd
-- ECE 2031 L13 — Final Version
-- Jaivardhan Jain, Atharva Kulkarni, Bret Harvey, Jad Kahla
--
-- Description:
--   This peripheral provides SCOMP with simultaneous access to all 8 analog
--   input channels. The peripheral continuously cycles through all 8 channels
--   in the background via 'SPI', storing each result in a dedicated register.
--   The SCOMP programmer reads any channel instantly by doing IN 0xC0 through
--   IN 0xC7. No channel select is needed, and no polling or waiting
--   is ever required.

-- The following libraries are just the standard imports
-- Importantly, the lpm library gives us the required bus driver
library ieee;
library lpm;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use lpm.lpm_components.all;

-- Overarching face of peripheral:
-- inputs speak SCOMP language
-- outputs speak SPI chip language
-- NOTE: IO_Data is inout since it carries data both ways depending on R/W
entity ADC_PERIPHERAL is
    port(
        CLOCK : in std_logic;
        RESETN : in std_logic;
        -- SCOMP I/O bus
        IO_ADDR : in std_logic_vector(10 downto 0);
        IO_DATA : inout std_logic_vector(15 downto 0);
        IO_READ : in std_logic;
        IO_WRITE : in std_logic;
        -- LTC2308 SPI physical pins
        ADC_CONVST : out std_logic;
        ADC_SCK : out std_logic;
        ADC_SDI : out std_logic;
        ADC_SDO : in std_logic
    );
end entity ADC_PERIPHERAL;


architecture internals of ADC_PERIPHERAL is

    -- This is a forward declaration of a separate VHDL called LTC...
    -- Like a class declaration in OOP, just declaring that such an entity exists
    component LTC2308_ctrl is
        generic (CLK_DIV : integer := 1);
        port (
            clk : in std_logic;
            nrst : in std_logic;
            start : in std_logic;
            tx_data : in std_logic_vector(11 downto 0);
            rx_data : out std_logic_vector(11 downto 0);
            busy : out std_logic;
            sclk : out std_logic;
            conv : out std_logic;
            mosi : out std_logic;
            miso : in std_logic
        );
    end component;

    -- An array of 8 twelve-bit registers
    -- One dedicated result register per channel
    type result_array_t is array (0 to 7) of std_logic_vector(11 downto 0);
    signal ch_results : result_array_t;

    -- Cycles ALL CHANNELS CONT. 
    -- NOTE: Replaced old channel_reg
    -- This runs automatically, always sampling
    signal ch_counter : integer range 0 to 7;

    -- These are internal wires connecting these files to the LTC
    -- txdata carries the congif. word in
    -- rxdata carries ADC result back
    -- busysig tells us if a conversion is in progress
    -- startsig triggers a new conversion
    signal tx_data_sig : std_logic_vector(11 downto 0);
    signal rx_data_sig : std_logic_vector(11 downto 0);
    signal busy_sig : std_logic;
    signal start_sig : std_logic;

    -- NOTE: A once cycle delayed copy of busySig
    -- we can compare the two and detect the exact moment busy falls from 1 to 0
    -- this tells us a conversion just finished
    signal busy_prev : std_logic;

    -- Counts from 0 to 249 repeatedly to generate periodic conversion
    signal start_cnt : integer range 0 to 249;

    -- Enable the bus driver when SCOMP is reading
    signal io_en : std_logic;

    -- Holds channel result when the address mux is selected
    signal selected_result : std_logic_vector(11 downto 0);

begin

    ---------------------------------------------------------------------------
    -- Build the 12-bit SPI config word from ch_counter.
    --
    -- LTC2308 DIN word (6 config bits + 6 padding zeros):
    --   Bit 5: S/D = 1  (single-ended, not differential)
    --   Bit 4: O/S = channel MSB
    --   Bit 3: S1  = channel middle bit
    --   Bit 2: S0  = channel LSB
    --   Bit 1: UNI = 1  (unipolar: 0 to Vref)
    --   Bit 0: SLP = 0  (no sleep mode)
    --
    -- conv_std_logic_vector converts ch_counter integer to a 3-bit std_logic_vector
    ---------------------------------------------------------------------------
tx_data_sig <= '1'
             & std_logic_vector(to_unsigned(7 - ch_counter, 3))(2)
             & std_logic_vector(to_unsigned(7 - ch_counter, 3))(1)
             & std_logic_vector(to_unsigned(7 - ch_counter, 3))(0)
             & '1'
             & '0'
             & "000000";

    ---------------------------------------------------------------------------
    -- Instantiate the SPI controller.
    -- CLK_DIV=1: SCK = 10MHz / 2 = 5MHz (max allowed: 40MHz)
    ---------------------------------------------------------------------------
    adc_ctrl : LTC2308_ctrl
        generic map (CLK_DIV => 1)
        port map(
            clk     => CLOCK,
            nrst    => RESETN,
            start   => start_sig,
            tx_data => tx_data_sig,
            rx_data => rx_data_sig,
            busy    => busy_sig,
            sclk    => ADC_SCK,
            conv    => ADC_CONVST,
            mosi    => ADC_SDI,
            miso    => ADC_SDO
        );

    ---------------------------------------------------------------------------
    -- Periodic Start Pulse Generator
    --
    -- Fires a one-cycle start='1' pulse every 250 clock cycles (25us at 10MHz).
    -- This keeps conversions running automatically without any SCOMP involvement.
    ---------------------------------------------------------------------------
    process(CLOCK, RESETN)
    begin
        if RESETN = '0' then
            start_cnt <= 0;
            start_sig <= '0';
        elsif rising_edge(CLOCK) then
            if start_cnt = 249 then
                start_cnt <= 0;
                start_sig <= '1';
            else
                start_cnt <= start_cnt + 1;
                start_sig <= '0';
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Channel Rotation and Result Latching
    --
    -- Monitors the busy signal. When busy falls from 1 to 0, a conversion
    -- has just completed. At that moment:
    --   1. Latch rx_data_sig into ch_results for the channel just sampled
    --   2. Increment ch_counter so the next conversion targets the next channel
    --
    -- After ch_counter reaches 7, it wraps back to 0, creating a continuous
    -- 0->1->2->3->4->5->6->7->0->... cycle through all 8 channels.
    ---------------------------------------------------------------------------
    process(CLOCK, RESETN)
begin
    if RESETN = '0' then
        busy_prev  <= '0';
        ch_counter <= 0;
        for i in 0 to 7 loop
            ch_results(i) <= (others => '0');
        end loop;
    elsif rising_edge(CLOCK) then
        busy_prev <= busy_sig;

        if busy_prev = '1' and busy_sig = '0' then
            -- Store result directly into current ch_counter
            -- ch_counter already points to the channel whose
            -- data just came back
            ch_results(ch_counter) <= rx_data_sig;
            
            -- Advance to next channel
            if ch_counter = 7 then
                ch_counter <= 0;
            else
                ch_counter <= ch_counter + 1;
            end if;
        end if;
    end if;
end process;

    ---------------------------------------------------------------------------
    -- Channel Result Mux
    --
    -- Uses the low 3 bits of IO_ADDR to select which channel result to drive.
    -- 0xC0 -> ch_results(0), 0xC1 -> ch_results(1), ..., 0xC7 -> ch_results(7)
    ---------------------------------------------------------------------------
    with IO_ADDR(2 downto 0) select
        selected_result <=
            ch_results(0) when "000",
            ch_results(1) when "001",
            ch_results(2) when "010",
            ch_results(3) when "011",
            ch_results(4) when "100",
            ch_results(5) when "101",
            ch_results(6) when "110",
            ch_results(7) when others;

    ---------------------------------------------------------------------------
    -- IO Bus Driver
    --
    -- Drives IO_DATA when SCOMP reads from any address 0xC0 through 0xC7.
    -- IO_ADDR[10:3] = "00011000" identifies our peripheral (upper bits of 0xCx).
    -- IO_ADDR[2:0]  selects the channel via the mux above.
    -- lpm_bustri tri-states the bus when io_en='0' so other peripherals
    -- can still drive IO_DATA.
    ---------------------------------------------------------------------------
    io_en <= '1' when IO_READ = '1'
                  and IO_ADDR(10 downto 3) = "00011000"
             else '0';

    io_bus : lpm_bustri
        generic map (lpm_width => 16)
        port map(
            data     => "0000" & selected_result,
            enabledt => io_en,
            tridata  => IO_DATA
        );

end architecture internals;
