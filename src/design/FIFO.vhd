----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 26.11.2026 08:38:35
-- Design Name: 
-- Module Name: FIFO - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity FIFO is
    Generic(
        FIFO_WIDTH : integer := 8;
        FIFO_DEPTH : integer := 16
    );
    
    Port(
        reset : in std_logic;
        clk : in std_logic;
        din : in std_logic_vector(FIFO_WIDTH-1 DOWNTO 0);
        dout : out std_logic_vector(FIFO_WIDTH-1 DOWNTO 0);
        rd_en : in std_logic;
        wr_en : in std_logic;
        full : out std_logic;
        empty : out std_logic
    );
end FIFO;

architecture Behavioral of FIFO is

    type My_array is array (integer range <>) of std_logic_vector(FIFO_WIDTH-1 DOWNTO 0);
    signal memoria_FIFO : My_array(FIFO_DEPTH-1 DOWNTO 0);
    signal is_full : std_logic;
    signal is_empty : std_logic;
    
begin
    
    process(clk, reset)
    variable 
        count : integer := 0;
    begin
        if reset = '1' then
            count := 0;
            memoria_FIFO <= (others => (others => '0'));
            is_full <= '0';
            is_empty <= '1';
            dout <= (others => '0');
        elsif rising_edge(clk) then
            if wr_en = '1' and not(is_full) = '1' and not(rd_en) = '1' then
                memoria_FIFO(count) <= din;
                count := count + 1;
                if count = FIFO_DEPTH then
                    is_full <= '1';
                end if;
            end if;
            
            if rd_en = '1' and not(is_empty) = '1' and not(wr_en) = '1' then
                dout <= memoria_FIFO(0);
                for i in 0 to FIFO_DEPTH-2 loop
                    memoria_FIFO(i) <= memoria_FIFO(i+1);
                end loop;
                count := count - 1;
                if count = 0 then
                    is_empty <= '1';
                end if;
            end if;
            
            if wr_en = '1' and not(is_full) = '1' and rd_en = '1' and not(is_empty) = '1' then
                dout <= memoria_FIFO(0);
                for i in 0 to FIFO_DEPTH-2 loop
                    memoria_FIFO(i) <= memoria_FIFO(i+1);
                end loop;
                 memoria_FIFO(count-1) <= din;
            end if;
            
            if wr_en = '1' and rd_en = '1' and is_full = '1' and not(is_empty) = '1' then 
                dout <= memoria_FIFO(0);
                for i in 0 to FIFO_DEPTH-2 loop
                    memoria_FIFO(i) <= memoria_FIFO(i+1);
                end loop;
                count := count - 1;
                if count = 0 then
                    is_empty <= '1';
                end if;
            end if;
            
            if wr_en = '1' and rd_en = '1' and is_empty = '1' and not(is_full) = '1' then
                memoria_FIFO(count) <= din;
                count := count + 1;
                if count = FIFO_DEPTH then
                    is_full <= '1';
                end if;
            end if;    
            
            if not(count = FIFO_DEPTH) then
                is_full <= '0';
            end if;
            
            if not(count = 0) then 
                is_empty <= '0';
            end if;
        end if;
            
    end process;

    full <= is_full;
    empty <= is_empty;
    
end Behavioral;
