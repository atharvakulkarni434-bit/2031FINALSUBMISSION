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

    -- builds the 12 bit SPI config. word that the ADC expects
    -- first one is single ended mode
    -- next 3 bits are channel number (7 - ch) corrects for channel mapping error discovered during tests
    -- then, the one is for unipolar
    -- 0 is for no sleep mode
    -- finally, six zeroes for padding
tx_data_sig <= '1'
             & std_logic_vector(to_unsigned(7 - ch_counter, 3))(2)
             & std_logic_vector(to_unsigned(7 - ch_counter, 3))(1)
             & std_logic_vector(to_unsigned(7 - ch_counter, 3))(0)
             & '1'
             & '0'
             & "000000";

    -- creates a physical instantiation of LTC and wires it up
    -- sends generic CLK_DIV a value of ONE
    adc_ctrl : LTC2308_ctrl
        generic map (CLK_DIV => 1)
        port map(
            clk => CLOCK,
            nrst => RESETN,
            start => start_sig,
            tx_data => tx_data_sig,
            rx_data => rx_data_sig,
            busy => busy_sig,
            sclk => ADC_SCK,
            conv => ADC_CONVST,
            mosi => ADC_SDI,
            miso => ADC_SDO
        );

    -- this is the start pulse generator
    -- counts from 0 to 249 on every clock edge
    -- then, fires a one-cycle start_dig = '1' pulse
    -- new conversion every 25 microseconds
    -- makes it so ADC samples all 8 channels cont.
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

    -- every clock edge, busy_prev records LAST cycle's busy value
    -- when busy was 1, and now zero, conversion finished
    -- then, result is latched, adn ch coutner advances to next channel
    -- this is how we sample all 8 channels continuously
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
            -- specifically, store result directly into current ch_counter
            -- ch_counter already points to the channel whose data is coming back
            ch_results(ch_counter) <= rx_data_sig;
            
            -- Then, we advance to next channel
            if ch_counter = 7 then
                ch_counter <= 0;
            else
                ch_counter <= ch_counter + 1;
            end if;
        end if;
    end if;
end process;

    -- this is a concurrent select statement
    -- low 3 bits of IO_ADDR directly indexed into ch results
    -- essentially, depending on the channel you want, sends these bits
    -- address starts with 000, then 001, 010, etc etc.
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

    -- io_en is only high when SCOMP is doing an IN from our address range
    --when we ARE doing in In, we drive the 12 bit result (padded to 16)
    io_en <= '1' when IO_READ = '1'
                  and IO_ADDR(10 downto 3) = "00011000"
             else '0';

    -- else, we leave it disconnected (high impedance) so other peripherals can still use the bus
    io_bus : lpm_bustri
        generic map (lpm_width => 16)
        port map(
            data     => "0000" & selected_result,
            enabledt => io_en,
            tridata  => IO_DATA
        );

end architecture internals;
