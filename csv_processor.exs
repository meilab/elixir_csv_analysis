defmodule Csv do
  def analyze_all(pathname) do
    filenames = File.ls! pathname

    filenames
      |> Enum.filter(fn name -> 
        (not String.contains?(name, "txt")) 
        && String.contains?(name, "CSV")
      end)
      |> Enum.map(fn (item) -> 
        filename = pathname <> "/" <> item
        main(filename) 
    end)

    # merge all the files
    analyzed_filenames = File.ls!

    merged_result =
      analyzed_filenames
        |> Enum.filter(fn name ->
          String.contains?(name, "txt")
        end)
        |> Enum.map(&File.read!/1)
        |> Enum.reduce("", &<>/2)

    File.write "merged.txt", merged_result  
  end

  def main(filename, start, length) do
    worker(filename, start, length)
  end

  def main(filename) do
    worker(filename, 10, 139990)
  end

  def worker(filename, start, length) do
    {result, _, _, _, _, _, _, _} =
      File.read!(filename)
      |> String.splitter("\n", trim: true)
      |> Enum.drop(start)
      |> Enum.take(length)
      |> Enum.map(fn( item )-> 
                    [_ | [clk | [ data ] ] ] = String.split( item, "," )
                    {String.to_float(clk), String.to_float(data)}
                  end 
                  )
      |> Enum.reduce({[], false, 0, 0, 0, 0, false, 0}, &toBinaryReducer/2)

    {resultHexClk, _, _, _, _, _, _} =
      result
        |> Enum.reduce({[], 0, 0, "", 4, 3, 1}, &toHexAccodingToClk/2)

    {resultHexDoubleClk, _, _, _, _, _, _} =
      result
        |> Enum.reduce({[], 0, 0, "", 2, 1, 3}, &toHexAccodingToClk/2)

        #IO.inspect result
        #IO.inspect resultHexClk
        #IO.inspect resultHexDoubleClk 

    {finalResult, _, _} =
      resultHexDoubleClk
        |> Enum.reduce({[], [], 0}, &removeConsecutiveZero/2)

    resultToStore =
      finalResult 
        |> Enum.join(",")

    filenameNoPath =
      filename
        |> String.split("/")
        |> Enum.at(-1)

    File.write filenameNoPath  <> ".txt", resultToStore 
  end

  defp removeConsecutiveZero(item, {final, tempArr, zeroCount}) do
    cond do
      (item == "0x00") && (zeroCount >= (zero_threshold()/8 - 2)) ->
        {final ++ [""], [], 0}
      (item == "0x00") ->
        {final, tempArr ++ [item], zeroCount + 1}
      true ->
        {final ++ tempArr ++ [item], [], 0}
    end
  end

  defp toHexAccodingToClk(item, {final, num, count, pendingItem, acc, incValue, countMax}) do
    newNum =
      if(item == 1) do
        num * acc + incValue
      else
        num * acc
      end

    newItem = pendingItem <> (numToHex newNum)

    cond do
      item == invalid_value() ->
        { final ++ ["\n"], 0, 0, "", acc, incValue, countMax }

      count < countMax ->
        { final, newNum, count + 1, pendingItem, acc, incValue, countMax }

      pendingItem == "" ->
        { final, 0, 0, "0x" <> newItem, acc, incValue, countMax }
      true ->
        { final ++ [newItem], 0, 0, "", acc, incValue, countMax }
    end
  end


  def toBinaryReducer({clk, data}, {final, decoding_start, last_clk, last_data, one_count, zero_count, clk_trigger, consecutive_zero_data}) do
    clk_value = analogToDigital(clk)
    data_value = analogToDigital(data)
    {new_decoding_start, new_consecutive_zero_data} =
      cond do
        (decoding_start == false) && (data_value == 1) ->
          #IO.puts "Start decoding"
          {true, consecutive_zero_data}
        consecutive_zero_data  >= zero_threshold() ->
          {false, 0}
        true ->
          {decoding_start, consecutive_zero_data}
      end

    {new_one_count, new_zero_count, add_value} =
      calc_new_one_zero(one_count, zero_count, data_value, new_decoding_start, last_data)

    new_clk_trigger =
      if (clk_value != last_clk) do
        true
      else
        clk_trigger
      end

      #IO.inspect {final, new_decoding_start, clk_value, data_value, new_one_count, new_zero_count, new_clk_trigger, new_consecutive_zero_data}

    cond do
      (decoding_start == true) && (new_decoding_start == false) ->
        {final ++ [invalid_value()], new_decoding_start, 0, 0, 0, 0, false, 0}

      last_clk == clk_value ->
        {final, new_decoding_start, clk_value, data_value, new_one_count, new_zero_count, new_clk_trigger, new_consecutive_zero_data}

      (new_one_count > 5) ->
        {final ++ add_value, new_decoding_start, clk_value, data_value, 0, rem(new_zero_count, 6), false, 0}

      (new_zero_count > 5) ->
        {final ++ add_value, new_decoding_start, clk_value, data_value, rem(new_one_count, 6), 0, false, new_consecutive_zero_data + 1}

      true ->
        {final ++ add_value, new_decoding_start, clk_value, data_value, rem(new_one_count, 6), rem(new_zero_count, 6), new_clk_trigger, new_consecutive_zero_data}
    end

  end

  defp calc_new_one_zero(one_count, zero_count, data_value, new_decoding_start, last_data) do
    ones = one_count + data_value
    zeros = zero_count + 1 - data_value

    add_value =
      cond do
        ones > 5 ->
          [1]
        zeros > 5 ->
          [0]
        true ->
          []
      end

    cond do
      (new_decoding_start == true) && (data_value == last_data) ->
        {ones, zeros, add_value}

      (new_decoding_start == true) && (data_value != last_data) ->
        {data_value, 1 - data_value, add_value}
      true ->
        {0, 0, add_value}
    end

  end

  defp invalid_value() do
    2
  end

  defp zero_threshold() do
    32
  end

  defp numToHex (num) do
    cond do
      (num == 0) ->
        "0"
      (num == 1) ->
        "1"
      (num == 2) ->
        "2"
      (num == 3) ->
        "3" 
      (num == 4) ->
        "4"
      (num == 5) ->
        "5"
      (num == 6) ->
        "6" 
      (num == 7) ->
        "7"
      (num == 8) ->
        "8"
      (num == 9) ->
        "9"
      (num == 10) -> 
        "A"
      (num == 11) ->
        "B"
      (num == 12) ->
        "C"
      (num == 13) ->
        "D"
      (num == 14) ->
        "E"
      (num == 15) ->
        "F"
    end
  end

  defp analogToDigital(data) do
    if data > 1.8 do
      1
    else
      0
    end
  end
end
