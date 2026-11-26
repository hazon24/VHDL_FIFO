--------------------------------------------------------------------------------
-- Testbench self-checking per la entity FIFO (ring buffer)
--
-- Assunzioni (coerenti con le slide):
--   * reset attivo ALTO (reset = '1')
--   * scrittura: al fronte di salita se wr_en='1' e full='0'
--   * lettura  : al fronte di salita se rd_en='1' e empty='0'; dout viene
--                aggiornato sul fronte (uscita registrata, vedi waveform)
--   * full / empty dipendono solo dal numero di parole memorizzate
--   * rd_en='1' e wr_en='1': se empty -> solo scrittura, se full -> solo
--                lettura, altrimenti entrambe
--
-- Il testbench contiene un modello di riferimento (scoreboard) e confronta
-- ad ogni ciclo full, empty e dout del DUT con quelli attesi.
-- Se la FIFO usa reset attivo basso, cambiare RESET_ACTIVE.
--------------------------------------------------------------------------------
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;
 
entity FIFO_tb is
end FIFO_tb;
 
architecture sim of FIFO_tb is
 
  -- Parametri da provare (modificabili: es. DEPTH = 4, 5, 16, 1000...)
  constant FIFO_WIDTH   : integer := 8;
  constant FIFO_DEPTH   : integer := 16;
  constant CLK_PERIOD   : time    := 10 ns;
  constant RESET_ACTIVE : std_logic := '1';
  constant RESET_IDLE   : std_logic := not RESET_ACTIVE;
 
  -- Segnali verso il DUT
  signal clk   : std_logic := '0';
  signal reset : std_logic := RESET_ACTIVE;
  signal din   : std_logic_vector(FIFO_WIDTH-1 downto 0) := (others => '0');
  signal dout  : std_logic_vector(FIFO_WIDTH-1 downto 0);
  signal rd_en : std_logic := '0';
  signal wr_en : std_logic := '0';
  signal full  : std_logic;
  signal empty : std_logic;
 
  -- Modello di riferimento
  signal m_count : integer range 0 to FIFO_DEPTH := 0;
  signal m_dout  : std_logic_vector(FIFO_WIDTH-1 downto 0) := (others => '0');
  signal m_rd    : std_logic := '0';   -- '1' se all'ultimo fronte e' avvenuta una lettura
 
  -- Controllo simulazione
  signal done      : boolean := false;
  signal err_count : integer := 0;
  signal chk_count : integer := 0;
 
  -- Valore massimo+1 dei dati generati (evita overflow di 2**WIDTH)
  function data_mod return integer is
  begin
    if FIFO_WIDTH >= 16 then
      return 2**16;
    else
      return 2**FIFO_WIDTH;
    end if;
  end function;
 
begin
 
  ------------------------------------------------------------------------------
  -- DUT
  ------------------------------------------------------------------------------
  dut : entity work.FIFO
    generic map (
      FIFO_WIDTH => FIFO_WIDTH,
      FIFO_DEPTH => FIFO_DEPTH
    )
    port map (
      reset => reset,
      clk   => clk,
      din   => din,
      dout  => dout,
      rd_en => rd_en,
      wr_en => wr_en,
      full  => full,
      empty => empty
    );
 
  ------------------------------------------------------------------------------
  -- Clock
  ------------------------------------------------------------------------------
  clk_gen : process
  begin
    while not done loop
      clk <= '0';
      wait for CLK_PERIOD/2;
      clk <= '1';
      wait for CLK_PERIOD/2;
    end loop;
    wait;
  end process;
 
  ------------------------------------------------------------------------------
  -- Modello di riferimento (FIFO "ideale")
  ------------------------------------------------------------------------------
  model : process (clk, reset)
    type mem_t is array (0 to FIFO_DEPTH-1) of std_logic_vector(FIFO_WIDTH-1 downto 0);
    variable mem    : mem_t;
    variable rp, wp : integer range 0 to FIFO_DEPTH-1 := 0;
    variable cnt    : integer range 0 to FIFO_DEPTH   := 0;
    variable do_rd, do_wr : boolean;
  begin
    if reset = RESET_ACTIVE then
      rp := 0; wp := 0; cnt := 0;
      m_count <= 0;
      m_rd    <= '0';
    elsif rising_edge(clk) then
      do_rd := (rd_en = '1') and (cnt > 0);
      do_wr := (wr_en = '1') and (cnt < FIFO_DEPTH);
      m_rd <= '0';
      if do_rd then
        m_dout <= mem(rp);
        m_rd   <= '1';
        rp  := (rp + 1) mod FIFO_DEPTH;
        cnt := cnt - 1;
      end if;
      if do_wr then
        mem(wp) := din;
        wp  := (wp + 1) mod FIFO_DEPTH;
        cnt := cnt + 1;
      end if;
      m_count <= cnt;
    end if;
  end process;
 
  ------------------------------------------------------------------------------
  -- Checker: confronta DUT e modello sul fronte di discesa
  ------------------------------------------------------------------------------
  checker : process
    variable exp_full, exp_empty : std_logic;
  begin
    wait until falling_edge(clk);
 
    if m_count = FIFO_DEPTH then exp_full := '1'; else exp_full := '0'; end if;
    if m_count = 0          then exp_empty := '1'; else exp_empty := '0'; end if;
 
    if full /= exp_full then
      report "ERRORE full: atteso " & std_logic'image(exp_full) &
             " ottenuto " & std_logic'image(full) &
             " (count modello = " & integer'image(m_count) & ")"
        severity error;
      err_count <= err_count + 1;
    end if;
 
    if empty /= exp_empty then
      report "ERRORE empty: atteso " & std_logic'image(exp_empty) &
             " ottenuto " & std_logic'image(empty) &
             " (count modello = " & integer'image(m_count) & ")"
        severity error;
      err_count <= err_count + 1;
    end if;
 
    -- dout e' significativo solo dopo una lettura valida
    if m_rd = '1' then
      if dout /= m_dout then
        report "ERRORE dout: atteso " & integer'image(to_integer(unsigned(m_dout))) &
               " ottenuto " &
               integer'image(to_integer(unsigned(dout)))
          severity error;
        err_count <= err_count + 1;
      end if;
    end if;
 
    chk_count <= chk_count + 1;
  end process;
 
  ------------------------------------------------------------------------------
  -- Stimoli
  ------------------------------------------------------------------------------
  stimulus : process
    variable ctr    : integer := 1;     -- dato progressivo (cambia ad ogni ciclo)
    variable seed1  : positive := 42;
    variable seed2  : positive := 4711;
    variable rnd    : real;
    variable p_wr   : real;
    variable p_rd   : real;
    variable w, r   : std_logic;
 
    -- Un ciclo di clock: imposta gli ingressi (dopo il fronte di discesa) e
    -- attende il fronte di discesa successivo.
    procedure cycle (w_i : std_logic; r_i : std_logic) is
    begin
      wr_en <= w_i;
      rd_en <= r_i;
      din   <= std_logic_vector(to_unsigned(ctr mod data_mod, FIFO_WIDTH));
      ctr   := ctr + 1;
      wait until falling_edge(clk);
    end procedure;
 
    procedure idle (n : natural) is
    begin
      for i in 1 to n loop
        cycle('0', '0');
      end loop;
    end procedure;
 
    procedure do_reset (n : natural) is
    begin
      reset <= RESET_ACTIVE;
      wr_en <= '0';
      rd_en <= '0';
      for i in 1 to n loop
        wait until falling_edge(clk);
      end loop;
      reset <= RESET_IDLE;
    end procedure;
 
  begin
    ----------------------------------------------------------------------------
    report "TEST 1: reset iniziale";
    wait until falling_edge(clk);
    do_reset(3);
    idle(2);
 
    ----------------------------------------------------------------------------
    report "TEST 2: una scrittura e una lettura";
    cycle('1', '0');
    idle(1);
    cycle('0', '1');
    idle(2);
 
    ----------------------------------------------------------------------------
    report "TEST 3: riempimento completo, scritture a FIFO piena (ignorate)";
    for i in 1 to FIFO_DEPTH loop
      cycle('1', '0');
    end loop;
    for i in 1 to 3 loop              -- scritture extra: NON devono essere salvate
      cycle('1', '0');
    end loop;
    idle(2);
 
    report "TEST 4: svuotamento completo, letture a FIFO vuota (ignorate)";
    for i in 1 to FIFO_DEPTH loop
      cycle('0', '1');
    end loop;
    for i in 1 to 3 loop              -- letture extra: nessun effetto
      cycle('0', '1');
    end loop;
    idle(2);
 
    ----------------------------------------------------------------------------
    report "TEST 5: lettura e scrittura simultanee a FIFO parzialmente piena";
    for i in 1 to FIFO_DEPTH/2 loop
      cycle('1', '0');
    end loop;
    for i in 1 to 3*FIFO_DEPTH loop   -- giro completo dei puntatori (wrap-around)
      cycle('1', '1');
    end loop;
    for i in 1 to FIFO_DEPTH/2 + 2 loop
      cycle('0', '1');
    end loop;
    idle(2);
 
    ----------------------------------------------------------------------------
    report "TEST 6: rd_en e wr_en insieme a FIFO vuota (solo scrittura)";
    cycle('1', '1');
    cycle('0', '0');
    cycle('0', '1');
    idle(2);
 
    ----------------------------------------------------------------------------
    report "TEST 7: rd_en e wr_en insieme a FIFO piena (solo lettura)";
    for i in 1 to FIFO_DEPTH loop
      cycle('1', '0');
    end loop;
    cycle('1', '1');                  -- full: solo lettura
    cycle('1', '1');                  -- ora c'e' un posto libero: entrambe
    cycle('0', '0');
    for i in 1 to FIFO_DEPTH + 2 loop
      cycle('0', '1');
    end loop;
    idle(2);
 
    ----------------------------------------------------------------------------
    report "TEST 8: reset a FIFO piena a meta'";
    for i in 1 to FIFO_DEPTH/2 loop
      cycle('1', '0');
    end loop;
    do_reset(2);
    idle(2);
    cycle('1', '0');                  -- dopo il reset deve funzionare normalmente
    cycle('0', '1');
    idle(2);
 
    ----------------------------------------------------------------------------
    report "TEST 9: traffico casuale (probabilita' variabili)";
    for phase in 0 to 3 loop
      case phase is
        when 0      => p_wr := 0.50; p_rd := 0.50;
        when 1      => p_wr := 0.90; p_rd := 0.20;   -- tende a riempirsi
        when 2      => p_wr := 0.20; p_rd := 0.90;   -- tende a svuotarsi
        when others => p_wr := 0.95; p_rd := 0.95;
      end case;
      for i in 1 to 1000 loop
        uniform(seed1, seed2, rnd);
        if rnd < p_wr then w := '1'; else w := '0'; end if;
        uniform(seed1, seed2, rnd);
        if rnd < p_rd then r := '1'; else r := '0'; end if;
        cycle(w, r);
      end loop;
    end loop;
    idle(3);
 
    ----------------------------------------------------------------------------
    -- Fine
    ----------------------------------------------------------------------------
    wait for 1 ns;
    report "Cicli controllati: " & integer'image(chk_count);
    if err_count = 0 then
      report "*** TEST SUPERATO: nessun errore ***" severity note;
    else
      report "*** TEST FALLITO: " & integer'image(err_count) & " errori ***"
        severity failure;
    end if;
    done <= true;
    wait;
  end process;
 
end sim;
 