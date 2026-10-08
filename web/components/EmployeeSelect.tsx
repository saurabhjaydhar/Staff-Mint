"use client";

import type { SelectHTMLAttributes } from "react";
import { useAsync } from "@/hooks/useAsync";
import { api } from "@/lib/api";
import type { Employee } from "@/lib/types";
import { Select } from "./ui";

/** Active employees, for pickers. */
export function useEmployees() {
  return useAsync(() => api.get<Employee[]>("/employees", { status: "active" }), "employees:active:picker");
}

export function EmployeeSelect({
  employees,
  placeholder = "Select employee",
  ...rest
}: SelectHTMLAttributes<HTMLSelectElement> & { employees: Employee[] | undefined; placeholder?: string }) {
  return (
    <Select {...rest}>
      <option value="">{placeholder}</option>
      {(employees ?? []).map((e) => (
        <option key={e.id} value={e.id}>
          {e.name} · {e.phone}
        </option>
      ))}
    </Select>
  );
}
