-----------------------------------------------------------------
--INP Projekt 1 Ovladánie maticového displaya--------------------
--Autor: Matej Dubec -- xdubec00 -- xdubec00@stud.fit.vutbr.cz---
-----------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_arith.all;
use IEEE.std_logic_unsigned.all;

entity ledc8x8 is
	port ( -- Sem doplnte popis rozhrani obvodu.
		SMCLK, RESET : in std_logic; -- signály: hlavný hodinový, asynchrónna inicializácia hodnôt
		LED : out std_logic_vector(0 to 7); -- signály pre LED
		ROW : out std_logic_vector(0 to 7) -- signály pre výber riadku matice	
	);
end ledc8x8;

architecture main of ledc8x8 is

	-- Sem doplnte definice vnitrnich signalu.
	 
	signal counter: std_logic_vector(11 downto 0) := (others => '0');  -- na pocitanie na rising edge
	signal counter1: std_logic_vector(20 downto 0) := (others => '0'); -- na zmenu stavu /4
	 
	signal active_row : std_logic_vector(7 downto 0) := "10000000";
	signal active_leds : std_logic_vector(7 downto 0) := (others => '1');
	
	signal state : std_Logic_vector(1 downto 0) := "00";
	signal ce: std_logic := '0';
	 								

begin

	 -- Sem doplnte popis obvodu. Doporuceni: pouzivejte zakladni obvodove prvky
    -- (multiplexory, registry, dekodery,...), jejich funkce popisujte pomoci
    -- procesu VHDL a propojeni techto prvku, tj. komunikaci mezi procesy,
    -- realizujte pomoci vnitrnich signalu deklarovanych vyse.

    -- DODRZUJTE ZASADY PSANI SYNTETIZOVATELNEHO VHDL KODU OBVODOVYCH PRVKU,
    -- JEZ JSOU PROBIRANY ZEJMENA NA UVODNICH CVICENI INP A SHRNUTY NA WEBU:
    -- http://merlin.fit.vutbr.cz/FITkit/docs/navody/synth_templates.html.

    -- Nezapomente take doplnit mapovani signalu rozhrani na piny FPGA
    -- v souboru ledc8x8.ucf.
	 

	-- delièka, 7,3mHz  /(256*8)
	clock_enable: process (SMCLK, RESET)
	begin
		if RESET = '1' then
			counter <= (others => '0'); -- vynulovanie 
		elsif rising_edge(SMCLK) then
			if counter = "111000010000" then
				ce <= '1';
				counter <= (others => '0');
         else
				counter <= counter + 1;
				ce <= '0';
         end if;
		end if;
	end process clock_enable;
	
	-- druhý generátor
	state_change: process (SMCLK, RESET)
	begin
		if RESET = '1' then
			state <= "00";
			counter1 <= (others => '0'); 
		elsif rising_edge(SMCLK) then
			if counter1 = "111000010000000000000" then
				state <= state + 1;
				counter1 <= (others => '0');
			else
            counter1 <= counter1 + 1;	
			end if;
		end if;
	end process state_change;

	-- rotacia riadkov, zacinam 1., dam RESET tak zasa na 1.
	rotation: process (SMCLK, RESET, ce)  
	begin
		if RESET = '1' then
			active_row <= "10000000";
	   elsif rising_edge(SMCLK) and ce = '1' then
			active_row <= active_row(0) & active_row(7 downto 1);
		end if;
	end process rotation; 
	
	-- dekoder
	-- vyberám aktívne LED v riadku, zasvietim LEDky ktore treba, striedam M, NIÈ, D, NIÈ pod¾a state vektora!
	process(active_row)
	begin
		if state = "00" then -- 00 ==> M
			case active_row is																																							
				when "10000000" => active_leds <= "01110111";
				when "01000000" => active_leds <= "00100111";
				when "00100000" => active_leds <= "01010111";
				when "00010000" => active_leds <= "01110111";
				when "00001000" => active_leds <= "01110111";
				when "00000100" => active_leds <= "11111111";
				when "00000010" => active_leds <= "11111111";
				when "00000001" => active_leds <= "11111111";
				when others => active_leds <= (others => '1');
			end case; 
		
		elsif state = "10" then	-- 10 ==> D
			case active_row is
				when "10000000" => active_leds <= "00001111";
				when "01000000" => active_leds <= "10110111";
				when "00100000" => active_leds <= "10110111";
				when "00010000" => active_leds <= "10110111";
				when "00001000" => active_leds <= "00001111";
				when "00000100" => active_leds <= "11111111";
				when "00000010" => active_leds <= "11111111";
				when "00000001" => active_leds <= "11111111";
				when others => active_leds <= (others => '1');
			end case;
				
		elsif state = "01" then	-- 01 ==> VSETKY LED na 1
			case active_row is
				when "10000000" => active_leds <= (others => '1');
				when "01000000" => active_leds <= (others => '1');
				when "00100000" => active_leds <= (others => '1');
				when "00010000" => active_leds <= (others => '1');
				when "00001000" => active_leds <= (others => '1');
				when "00000100" => active_leds <= (others => '1');
				when "00000010" => active_leds <= (others => '1');
				when "00000001" => active_leds <= (others => '1');
				when others => active_leds <= (others => '1');
			end case;

		elsif state = "11" then	-- 11 ==> VSETKY LED na 1
			case active_row is
				when "10000000" => active_leds <= (others => '1');
				when "01000000" => active_leds <= (others => '1');
				when "00100000" => active_leds <= (others => '1');
				when "00010000" => active_leds <= (others => '1');
				when "00001000" => active_leds <= (others => '1');
				when "00000100" => active_leds <= (others => '1');
				when "00000010" => active_leds <= (others => '1');
				when "00000001" => active_leds <= (others => '1');
				when others => active_leds <= (others => '1');
			end case;
		end if;
	end process;
	
	-- nastavene LED aktuálnymi signálmi active_leds
	LED <= active_leds;
	ROW <= active_row;

end main;
