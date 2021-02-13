-- cpu.vhd: Simple 8-bit CPU (BrainF*ck interpreter)
-- Copyright (C) 2018 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): xdubec00
--

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
 
		-- synchronni pamet ROM
		CODE_ADDR : out std_logic_vector(11 downto 0); -- adresa do pameti
		CODE_DATA : in std_logic_vector(7 downto 0);   -- CODE_DATA <- rom[CODE_ADDR] pokud CODE_EN='1'
		CODE_EN   : out std_logic;                     -- povoleni cinnosti
   
		-- synchronni pamet RAM
		DATA_ADDR  : out std_logic_vector(9 downto 0); -- adresa do pameti
		DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
		DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
		DATA_RDWR  : out std_logic;                    -- cteni z pameti (DATA_RDWR='1') / zapis do pameti (DATA_RDWR='0')
		DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
		-- vstupni port
		IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA obsahuje stisknuty znak klavesnice pokud IN_VLD='1' a IN_REQ='1'
		IN_VLD    : in std_logic;                      -- data platna pokud IN_VLD='1'
		IN_REQ    : out std_logic;                     -- pozadavek na vstup dat z klavesnice
   
		-- vystupni port
		OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
		OUT_BUSY : in std_logic;                       -- pokud OUT_BUSY='1', LCD je zaneprazdnen, nelze zapisovat,  OUT_WE musi byt '0'
		OUT_WE   : out std_logic                       -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
	);
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is

	
   signal mux: std_logic_vector(1 downto 0); -- multiplexor
   signal muxmem: std_logic_vector(7 downto 0); -- pamat pre MPLEXOR
	
   signal pc_inc: std_logic;							
   signal pc_dec: std_logic;							
   signal pc_out: std_logic_vector(11 downto 0);  -- PC
   	
   signal ptr_inc: std_logic;
   signal ptr_dec: std_logic;
	signal ptr_out: std_logic_vector(9 downto 0);  -- PTR
	
   signal cnt_inc: std_logic;
   signal cnt_dec: std_logic;
	signal cnt_out: std_logic_vector(7 downto 0);  -- CNT
	 
   type fsm_state is (
		fetch, -- nacitaj stav
		decode, -- dekoduj
      INCa, DECa, -- ptr++; ptr--;
      INCb, DECb, -- *ptr++; *ptr--;
		INCb1, DECb1,				-- nasledujuci stav po INCb / DECb
		BRACl, -- while () {
		BRACl1, BRACl2,BRACl3, 	-- stavy nasledujuce po BRACl
		BRACr, -- while () }
		BRACr1, BRACr2, BRACr3, BRACr4, BRACr5, 
		DOT,   -- putchar(*ptr);
		DOTa,  -- nasledujuci stav po DOT, ak pri DOT neplati (OUT_BUSY = '1')
		COMMA, -- *ptr = getchar();
		HASHT, -- /* ... */
		HASHTa, -- nasledujuci stav po HASHT (CODE_EN = 1)
		HASHTb, -- nasledujuci stav po HASHTa (ak dostanem # -> koniec komentaru; else -> HASHT)
		VALn, -- *ptr = 0x(HEXA); HEXA znaky -> [0-9];
		VALc, -- *ptr = 0x(HEXA); HEXA znaky -> [A-F];
		RETn, -- return; (koniec programu) - koncovy stav
      UNKNOWN -- nepoznany znak v CODE_DATA, iny ako mam prijimat -> nacitavam dalsi znak.
   );
	 
   signal present_state: fsm_state; -- signaly reprezentujuce momentalny a nasledujuci stav v automate
   signal next_state: fsm_state;
 

 -- zde dopiste potrebne deklarace signalu  

begin
	
	-- Multiplexor
	MPX: process(mux, muxmem, IN_DATA, DATA_RDATA)
	begin
		case (mux) is
			when "11" => DATA_WDATA <= muxmem;
			when "00" => DATA_WDATA <= IN_DATA;
			when "10" => DATA_WDATA <= DATA_RDATA - 1;
			when "01" => DATA_WDATA <= DATA_RDATA + 1;
			when others =>
		end case;
	end process;
	
	-- register PC -> programovy citac
	PC: process(CLK, RESET, pc_out, pc_inc, pc_dec)
	begin
		if(RESET = '1') then
			pc_out <= (others => '0'); 
		elsif rising_edge(CLK) then
			if(pc_inc = '1') then
				pc_out <= pc_out + 1; 
			elsif(pc_dec = '1') then
				pc_out <= pc_out - 1;
			end if;
		end if;
		CODE_ADDR <= pc_out;
	end process;
	
	-- register PTR -> ukazatel do pamati dat
	PTR: process(CLK, RESET, ptr_out, ptr_inc, ptr_dec) 
	begin
		if(RESET = '1') then
			ptr_out <= (others => '0'); 
		elsif rising_edge(CLK) then
			if(ptr_inc = '1') then
				ptr_out <= ptr_out + 1;
			elsif(ptr_dec = '1') then
				ptr_out <= ptr_out - 1;
			end if;
		end if;
		DATA_ADDR <= ptr_out;
	end process;
 
	-- register CNT 
	CNT: process(CLK, RESET, cnt_inc, cnt_dec) 
	begin
		if(RESET = '1') then
			cnt_out <= (others => '0'); 
		elsif rising_edge(CLK) then
			if(cnt_inc = '1') then
				cnt_out <= cnt_out + 1;
			elsif(cnt_dec = '1') then
				cnt_out <= cnt_out - 1;
			end if;
		end if;
	end process;
 
	-- PSTATE
	PSTATE: process(CLK, RESET)
	begin
		if(RESET = '1') then
			present_state <= fetch;
		elsif( rising_edge(CLK) and EN = '1') then   
			present_state <= next_state;
		end if;
	end process;
 
	fsm_automat: process(CODE_DATA, DATA_RDATA, IN_VLD, OUT_BUSY, cnt_out, present_state) -- stavovy automat
	begin
	
		pc_inc <= '0';
		pc_dec <= '0';
		ptr_inc <= '0';
		ptr_dec <= '0';
		cnt_inc <= '0';
		cnt_dec <= '0';
		CODE_EN <= '1';
		DATA_EN <= '0';
		OUT_WE <= '0';
		IN_REQ <= '0';
		DATA_RDWR <= '0';
		mux <= "00";
		
       
		case present_state is -- momentalny stav
			when fetch =>		 -- idem dekodovat
				CODE_EN <= '1';
				next_state <= decode;
			when decode =>  	 --"dekodovanie" jednotlivych instrukcnych slov (8bit)
				case(CODE_DATA) is -- stavy reprezentuju postupnost akcii, ktore treba vykonat (podla pseudokodu v pdf ku projektu) v ktorom pripade
					when X"00" => next_state <= RETn;
					when X"3E" => next_state <= INCa;
					when X"3C" => next_state <= DECa;
					when X"2B" => next_state <= INCb;
					when X"2D" => next_state <= DECb;
					when X"5B" => next_state <= BRACl;
					when X"5D" => next_state <= BRACr;
					when X"2E" => next_state <= DOT;
					when X"2C" => next_state <= COMMA;
					when X"23" => next_state <= HASHT;
					when X"30" => next_state <= VALn;
					when X"31" => next_state <= VALn;
					when X"32" => next_state <= VALn;
					when X"33" => next_state <= VALn;
					when X"34" => next_state <= VALn;
					when X"35" => next_state <= VALn;
					when X"36" => next_state <= VALn;
					when X"37" => next_state <= VALn;
					when X"38" => next_state <= VALn;                    
					when X"39" => next_state <= VALn;
					when X"41" => next_state <= VALc;
					when X"42" => next_state <= VALc;
					when X"43" => next_state <= VALc;
					when X"44" => next_state <= VALc;
					when X"45" => next_state <= VALc;
					when X"46" => next_state <= VALc;
					when others => next_state <= UNKNOWN;
				end case;  
			when INCa => -- '>' == ptr++;
				ptr_inc <= '1';
				pc_inc <= '1';
				next_state <= fetch;
			when DECa => -- '<' == ptr--;
				ptr_dec <= '1';
				pc_inc <= '1';
				next_state <= fetch;
			when INCb => -- '+' == *ptr++;
				DATA_EN <= '1';
				DATA_RDWR <= '1';
				next_state <= INCb1;
			when INCb1 => -- stav po INCb
				mux <= "01";
				DATA_EN <= '1';
				DATA_RDWR <= '0';
				pc_inc <= '1';
				next_state <= fetch;
			when DECb => -- '-' == *ptr--;
				DATA_EN <= '1';
				DATA_RDWR <= '1';
				next_state <= DECb1;
			when DECb1 => -- stav po DECb
				mux <= "10";
				DATA_EN <= '1';
				DATA_RDWR <= '0';
				pc_inc <= '1';
				next_state <= fetch;
			when DOT => -- '.' == putchar(*ptr);
				if(OUT_BUSY = '1') then
					next_state <= DOT;
				else
					DATA_EN <= '1';
					DATA_RDWR <= '1';
					next_state <= DOTa;
				end if;
			when DOTa => -- stav po DOT
				OUT_WE <= '1';
				OUT_DATA <= DATA_RDATA;
				pc_inc <= '1';
				next_state <= fetch;
			when COMMA => -- ',' == *ptr = getchar();
				IN_REQ <= '1';
				if(IN_VLD = '0') then
					next_state <= COMMA;
				else
					mux <= "00";
					DATA_EN <= '1';
					DATA_RDWR <= '0';
					pc_inc <= '1';
					next_state <= fetch;
				end if;
			when BRACl => -- '[' == while (*ptr) {
				pc_inc <= '1';
				DATA_EN <= '1';
				DATA_RDWR <= '1';
				next_state <= BRACl1;
			when BRACl1 => -- nasledujuci stav po BRACl
				if(DATA_RDATA = "00000000") then
					cnt_inc <= '1';
					next_state <= BRACl2;
				else
					next_state <= fetch;
				end if;
			when BRACl2 => -- nasledujuci stav po BRACl3, mozny nasledujuci stav po BRACl1
				if(cnt_out = "00000000") then
					next_state <= fetch;
				else
					CODE_EN <= '1';
					next_state <= BRACl3;
				end if;
			when BRACl3 => -- mozny nasledujuci stav po BRACl2
				if(CODE_DATA = X"5B") then -- [
					cnt_inc <= '1';
				elsif(CODE_DATA = X"5D") then -- ]
					cnt_dec <= '1';
				end if;
				pc_inc <= '1';
				next_state <= BRACl2;
			when BRACr => -- ']' == }
				DATA_EN <= '1';
				DATA_RDWR <= '1';
				next_state <= BRACr1;
			when BRACr1 => -- nasledujuci stav po BRACr
				if(DATA_RDATA = "00000000") then
					pc_inc <= '1';
               next_state <= fetch;
				else
					next_state <= BRACr2;
				end if;
			when BRACr2 => -- mozny nasledujuci stav po BRACr1
				cnt_inc <= '1';
				pc_dec <= '1';
				next_state <= BRACr3;
			when BRACr3 => -- nasledujuci stav po BRACr2, BRACr5
				if(cnt_out = "00000000") then
					next_state <= fetch;
				else
					CODE_EN <= '1';
					next_state <= BRACr4;
				end if;
			when BRACr4 => -- mozny nasledujuci stav po BRACr3
				if(CODE_DATA = X"5D") then
					cnt_inc <= '1';
				elsif(CODE_DATA = X"5B") then
					cnt_dec <= '1';
				end if;
				next_state <= BRACr5;
			when BRACr5 => -- nasledujuci stav po BRACr4
				if(cnt_out = "00000000") then
					pc_inc <= '1';
				else
					pc_dec <= '1';
				end if;
				next_state <= BRACr3;
			when HASHT => -- '#' == /*...*/
				pc_inc <= '1';
				next_state <= HASHTa;
			when HASHTa => -- nasledujuci stav po HASHT
				CODE_EN <= '1';
				next_state <= HASHTb;
			when HASHTb => -- nasledujuci stav po HASHTa
				if CODE_DATA = X"23" then -- ak v CODE_DATA '#'
					pc_inc <= '1';
					next_state <= fetch;
				else
					next_state <= HASHT;
				end if;
			when VALn => -- '(0-9)' == *ptr = 0xV0; V = (0 - 9)
				DATA_EN <= '1';
				pc_inc <= '1';
				mux <= "11";
				muxmem <= CODE_DATA(3 downto 0) & X"0";
				next_state <= fetch;
			when VALc => -- '(A-F)' == *ptr = 0xV0; V = (A - F)
				DATA_EN <= '1';
				pc_inc <= '1';
				mux <= "11";
				muxmem <= (CODE_DATA(3 downto 0) + std_logic_vector(conv_unsigned(9, muxmem'LENGTH)(3 downto 0))) & "0000";
				next_state <= fetch;  
			when RETn =>    -- 'null' == return;
				next_state <= RETn;
			when UNKNOWN =>  
				pc_inc <= '1';
				next_state <= fetch;
			when others =>
		end case;
    end process;
end behavioral;



 
