-- cpu.vhd: Simple 8-bit CPU (BrainF*ck interpreter)
-- Copyright (C) 2019 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): Iveta Strnadova, xstrna14
-- verze 3 - funkcni zanorene while

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (0) / zapis (1)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_WE   : out std_logic                       -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is

 -- zde dopiste potrebne deklarace signalu
	signal MX2_OUT: std_logic_vector(12 downto 0); 		-- vystup MX2
	signal SEL_MX1: std_logic;							-- select pro mx1
	signal SEL_MX2: std_logic;							-- select pro mx2
	signal SEL_MX3: std_logic_vector(1 downto 0); 		-- select pro mx3
	signal PC_INC: std_logic;							-- 1 má-li se inkrementovat
	signal PC_DEC: std_logic;							-- 1 ma-li se dekrementovat
	signal PC_OUT: std_logic_vector(12 downto 0);		-- vystupni adresa z PC
	signal PTR_INC: std_logic;							-- inc pro ptr
	signal PTR_DEC: std_logic;
	signal PTR_OUT: std_logic_vector(12 downto 0);		-- vystupni adresa z PTR citace
	signal CNT_OUT: std_logic_vector(7 downto 0);		--vystup z cnt while zanoreni
	signal CNT_INC: std_logic;							--signal, ze chceme inkrementovat cnt while zanoreni
	signal CNT_DEC: std_logic;
	
	--FSM stuff
	type FSMstate is (
		init,
		balancer,
		data_next,
		data_prev,
		wait_before_load,
		load_instr, work_out_instr,
		data_add_a,
		data_sub_a,
		data_print_a,
		data_get_a,
		temp_load_a,
		temp_store_a,
		while_start_a,
		while_end_a,
		flush_right_a, flush_right_b,
		flush_left_a, flush_left_b, flush_left_c,
		other_stuff,
		end_state
	);
	signal pres_state : FSMstate;
	signal next_state : FSMstate;
	
begin

 -- zde dopiste vlastni VHDL kod
 -- pri tvorbe kodu reflektujte rady ze cviceni INP, zejmena mejte na pameti, ze 
 --   - nelze z vice procesu ovladat stejny signal,
 --   - je vhodne mit jeden proces pro popis jedne hardwarove komponenty, protoze pak
 --   - u synchronnich komponent obsahuje sensitivity list pouze CLK a RESET a 
 --   - u kombinacnich komponent obsahuje sensitivity list vsechny ctene signaly.
 
	--MX1 - multiplexor volici mezi vystupem z PC_OUT a MX2_OUT podle SEL_MX1
	mx1: process (PC_OUT, MX2_OUT, SEL_MX1)
		begin
			case SEL_MX1 is
				when '1' => DATA_ADDR <= MX2_OUT;
				when others => DATA_ADDR <= PC_OUT;
			end case;
	end process mx1;
	
	--MX2 - multiplexor volici mezi vystupem z PTR_OUT nebo default 0x1000 (adresa temp promenne) podle SEL_MX2
	mx2: process (PTR_OUT, SEL_MX2)
		begin
			case SEL_MX2 is
				when '1' => MX2_OUT <= "1000000000000";
				when others => MX2_OUT <= PTR_OUT;
			end case;
	end process mx2;
	
	--MX3 - multiplexor volici mezi IN_DATA, DATA_RDATA s odectenim 1, prictenim 1, nezmenena
	mx3: process (IN_DATA, DATA_RDATA, SEL_MX3)
		begin
			case SEL_MX3 is
				when "00" => DATA_WDATA <= IN_DATA;
				when "01" => DATA_WDATA <= DATA_RDATA - 1;
				when "10" => DATA_WDATA <= DATA_RDATA + 1;
				when others => DATA_WDATA <= DATA_RDATA;
			end case;
	end process mx3;
 
	--programovy citac (PC)
	pc: process(RESET, CLK)
		begin
			if(RESET = '1') then
				PC_OUT <= (others => '0');
			elsif(rising_edge(CLK)) then
				if(PC_INC = '1') then
					if(PC_OUT = "0111111111111") then
						PC_OUT <= "0000000000000";
					else 
						PC_OUT <= PC_OUT + 1;
					end if;
				elsif(PC_DEC = '1') then
					if(PC_OUT = "0000000000000") then
						PC_OUT <= "0111111111111";
					else
						PC_OUT <= PC_OUT - 1;
					end if;
				end if;
			end if;
	end process pc;
	
	--citac adresy do pameti (PTR)
	ptr: process(RESET, CLK)
		begin
			if(RESET = '1') then
				PTR_OUT <= "1000000000000";
			elsif(rising_edge(CLK)) then
				if(PTR_INC = '1') then
					if(PTR_OUT = "1111111111111") then
						PTR_OUT <= "1000000000000";
					else 
						PTR_OUT <= PTR_OUT + 1;
					end if;
				elsif(PTR_DEC = '1') then
					if(PTR_OUT = "1000000000000") then
						PTR_OUT <= "1111111111111";
					else
						PTR_OUT <= PTR_OUT - 1;
					end if;
				end if;
			end if;
	end process ptr;
 
	--citac while zanoreni
	while_cnt: process(RESET, CLK)
		begin
			if(RESET = '1') then
				CNT_OUT <= "00000000";
			elsif(rising_edge(CLK)) then
				if(CNT_INC = '1') then
					CNT_OUT <= CNT_OUT + 1;
				elsif(CNT_DEC = '1') then
					CNT_OUT <= CNT_OUT - 1;
				end if;
			end if;
	end process while_cnt;
	
	--FSM
	--present_state_registr
	pres_state_reg: process(RESET, CLK)
	begin
		if RESET = '1' then
			pres_state <= init;
		elsif rising_edge(CLK) then
			if(EN = '1') then
				pres_state <= next_state;
			end if;
		end if;
	end process;
	
	--Next State logic and output logic
	next_state_logic: process(CLK, RESET) --z nejakeho duvodu jen pres_state misto clk a reset nestacilo
	begin
		-- default
		DATA_RDWR <= '0';
		DATA_EN <= '0';
		IN_REQ <= '0';
		OUT_WE <= '0';
		
		PC_INC <= '0';
		PC_DEC <= '0';
		PTR_INC <= '0';
		PTR_DEC <= '0';
		CNT_INC <= '0';
		CNT_DEC <= '0';
		
		-- next_state
		case pres_state is
			when init =>
				--inicializace na nejakou hodnotu, aby nebylo nedefinovane
				SEL_MX1 <= '0';
				SEL_MX2 <= '0';
				SEL_MX3 <= "00";
				DATA_RDWR <= '0';
				
				if(RESET = '1') then
					next_state <= init;
				else
					next_state <= load_instr;
				end if;
				
			when load_instr =>
				--load instrukce do DATA_RDATA
				DATA_RDWR <= '0';
				SEL_MX1 <= '0';
				SEL_MX2 <= '0';
				SEL_MX3 <= "00";
				
				DATA_EN <= '1';
				next_state <= work_out_instr;
				
			when work_out_instr =>
				--rozhodnuti dalsiho stavu podle nactene instukce
				case DATA_RDATA is
					when X"3E" => -- >
						PTR_INC <= '1';
						PC_INC <= '1';
						next_state <= load_instr;
					when X"3C" => -- <
						PTR_DEC <= '1';
						PC_INC <= '1';
						next_state <= load_instr;
					when X"2B" => -- +
						SEL_MX1 <= '1';
						SEL_MX2 <= '0';
						SEL_MX3 <= "10";
						DATA_RDWR <= '0';
						DATA_EN <= '1';
						next_state <= data_add_a;
					when X"2D" => -- -
						SEL_MX1 <= '1';
						SEL_MX2 <= '0';
						SEL_MX3 <= "01";
						DATA_RDWR <= '0';
						DATA_EN <= '1';
						next_state <= data_sub_a;
					when X"5B" => -- [
						SEL_MX2 <= '0';
						SEL_MX1 <= '1';
						SEL_MX3 <= "11";
						DATA_RDWR <= '0';
						DATA_EN <= '1';
						next_state <= while_start_a;
					when X"5D" => -- ]
						SEL_MX2 <= '0';
						SEL_MX1 <= '1';
						SEL_MX3 <= "11";
						DATA_RDWR <= '0';
						DATA_EN <= '1';
						next_state <= while_end_a;
					when X"2E" => -- .
						SEL_MX1 <= '1';
						SEL_MX2 <= '0';
						SEL_MX3 <= "11";
						DATA_RDWR <= '0';
						DATA_EN <= '1';
						next_state <= data_print_a;
					when X"2C" => -- ,
						IN_REQ <= '1';
						next_state <= data_get_a;
					when X"24" => -- $
						SEL_MX2 <= '0';
						SEL_MX1 <= '1';
						SEL_MX3 <= "11";
						DATA_RDWR <= '0';
						DATA_EN <= '1';
						next_state <= temp_store_a;
					when X"21" => -- !
						SEL_MX1 <= '1';
						SEL_MX2 <= '1';
						SEL_MX3 <= "11";
						DATA_RDWR <= '0';
						DATA_EN <= '1';
						next_state <= temp_load_a;
					when X"00" => -- null
						next_state <= end_state;
					when others =>
						next_state <= other_stuff;
				end case;
				
			when data_add_a =>
				SEL_MX1 <= '1';
				SEL_MX2 <= '0';
				SEL_MX3 <= "10";
				DATA_RDWR <= '1';
				DATA_EN <= '1';
				--zapise se pri dalsim tiku, skonci
				PC_INC <= '1';
				next_state <= load_instr;
				
			when data_sub_a =>
				SEL_MX1 <= '1';
				SEL_MX2 <= '0';
				SEL_MX3 <= "01";
				DATA_RDWR <= '1';
				DATA_EN <= '1';
				--zapise se pri dalsim tiku, skonci
				PC_INC <= '1';
				next_state <= load_instr;
				
			when data_get_a =>
				if (IN_VLD = '1') then
					SEL_MX3 <= "00";
					SEL_MX1 <= '1';
					SEL_MX2 <= '0';
					DATA_RDWR <= '1';
					DATA_EN <= '1';
					PC_INC <= '1';
					next_state <= load_instr;
				else
					IN_REQ <= '1';
					next_state <= data_get_a;
				end if;
				
			when temp_load_a =>
				SEL_MX1 <= '1';
				SEL_MX2 <= '0';
				SEL_MX3 <= "11";
				DATA_RDWR <= '1';
				DATA_EN <= '1';
				PC_INC <= '1';
				next_state <= load_instr;
			
			when temp_store_a =>
				SEL_MX3 <= "11";
				SEL_MX2 <= '1';
				SEL_MX1 <= '1';
				DATA_RDWR <= '1';
				DATA_EN <= '1';
				PC_INC <= '1';
				next_state <= load_instr;
				
			when data_print_a =>
				if(OUT_BUSY = '0') then
					OUT_DATA <= DATA_RDATA;
					OUT_WE <= '1';
					PC_INC <= '1';
					next_state <= load_instr;
				else
					--aktivni cekani na to, az bude out volny
					next_state <= data_print_a;
				end if;
				
			when while_start_a =>
				if(DATA_RDATA = "00000000") then
					next_state <= flush_right_a;
				else
					next_state <= load_instr;
				end if;
				PC_INC <= '1';
				
			when flush_right_a =>
				SEL_MX1 <= '0';
				SEL_MX2 <= '1';
				SEL_MX3 <= "11";
				DATA_RDWR <= '0';
				DATA_EN <= '1';
				next_state <= flush_right_b;
				
			when flush_right_b =>
				if(DATA_RDATA = X"5D") then
					if(CNT_OUT = "00000000") then
						PC_INC <= '1';
						next_state <= load_instr;
					else
						CNT_DEC <= '1';
						PC_INC <= '1';
						next_state <= flush_right_a;
					end if;
				elsif(DATA_RDATA = X"5B") then
					PC_INC <= '1';
					CNT_INC <= '1';
					next_state <= flush_right_a;
				else
					PC_INC <= '1';
					next_state <= flush_right_a;
				end if;
			
			when while_end_a =>
				if(DATA_RDATA = "00000000") then
					PC_INC <= '1';
					next_state <= load_instr;
				else
					PC_DEC <= '1';
					next_state <= flush_left_a;
				end if;
				
			when flush_left_a =>
				SEL_MX1 <= '0';
				SEL_MX2 <= '1';
				SEL_MX3 <= "11";
				DATA_RDWR <= '0';
				DATA_EN <= '1';
				next_state <= flush_left_b;
				
			when flush_left_b =>
				if(DATA_RDATA = X"5B") then
					if(CNT_OUT = "00000000") then
						PC_INC <= '1';
						next_state <= load_instr;
					else
						PC_DEC <= '1';
						CNT_DEC <= '1';
						next_state <= flush_left_a;
					end if;
				elsif(DATA_RDATA = X"5D") then
					PC_DEC <= '1';
					CNT_INC <= '1';
					next_state <= flush_left_a;
				else
					PC_DEC <= '1';
					next_state <= flush_left_a;
				end if;
				
			when other_stuff =>
				PC_INC <= '1';
				next_state <= load_instr;
				
			when end_state =>
				next_state <= end_state;
			when others => null;
		end case;
	end process;
	
 
end behavioral;
 
