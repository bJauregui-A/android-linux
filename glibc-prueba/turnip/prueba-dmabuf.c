/* Prueba de memoria exportable de Turnip (reservada por el anfitrión, parche 0001):
   reserva, escribe por vkMapMemory, exporta el dmabuf y lo lee por mmap.
   gcc -O2 -o prueba-dmabuf prueba-dmabuf.c -lvulkan  */
#include <stdio.h>
#include <stdint.h>
#include <sys/mman.h>
#include <unistd.h>
#include <vulkan/vulkan.h>

#define OK(x) do { VkResult r_ = (x); if (r_ != VK_SUCCESS) { printf ("fallo %s: %d\n", #x, r_); return 1; } } while (0)

int
main (void)
{
  VkInstance inst;
  VkInstanceCreateInfo ici = { .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
    .pApplicationInfo = &(VkApplicationInfo) { .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO, .apiVersion = VK_API_VERSION_1_1 } };
  OK (vkCreateInstance (&ici, NULL, &inst));
  uint32_t n = 1;
  VkPhysicalDevice pd;
  vkEnumeratePhysicalDevices (inst, &n, &pd);
  const char *ext[] = { "VK_KHR_external_memory_fd", "VK_EXT_external_memory_dma_buf" };
  float prio = 1;
  VkDeviceCreateInfo dci = { .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
    .queueCreateInfoCount = 1,
    .pQueueCreateInfos = &(VkDeviceQueueCreateInfo) { .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, .queueCount = 1, .pQueuePriorities = &prio },
    .enabledExtensionCount = 2, .ppEnabledExtensionNames = ext };
  VkDevice dev;
  OK (vkCreateDevice (pd, &dci, NULL, &dev));

  VkPhysicalDeviceMemoryProperties mp;
  vkGetPhysicalDeviceMemoryProperties (pd, &mp);
  uint32_t tipo = 0;
  for (uint32_t i = 0; i < mp.memoryTypeCount; i++)
    if (mp.memoryTypes[i].propertyFlags & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT)
      { tipo = i; break; }

  const VkDeviceSize TAM = 4 << 20;
  VkExportMemoryAllocateInfo exp = { .sType = VK_STRUCTURE_TYPE_EXPORT_MEMORY_ALLOCATE_INFO,
    .handleTypes = VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT };
  VkMemoryAllocateInfo mai = { .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .pNext = &exp,
    .allocationSize = TAM, .memoryTypeIndex = tipo };
  VkDeviceMemory mem;
  OK (vkAllocateMemory (dev, &mai, NULL, &mem));
  uint32_t *p;
  OK (vkMapMemory (dev, mem, 0, TAM, 0, (void **) &p));
  for (uint32_t i = 0; i < TAM / 4; i++)
    p[i] = i * 2654435761u;

  PFN_vkGetMemoryFdKHR getfd = (PFN_vkGetMemoryFdKHR) vkGetDeviceProcAddr (dev, "vkGetMemoryFdKHR");
  int fd;
  OK (getfd (dev, &(VkMemoryGetFdInfoKHR) { .sType = VK_STRUCTURE_TYPE_MEMORY_GET_FD_INFO_KHR,
    .memory = mem, .handleType = VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT }, &fd));
  off_t t = lseek (fd, 0, SEEK_END);
  uint32_t *q = mmap (NULL, TAM, PROT_READ, MAP_SHARED, fd, 0);
  if (q == MAP_FAILED) { perror ("mmap dmabuf"); return 1; }
  uint32_t malos = 0;
  for (uint32_t i = 0; i < TAM / 4; i++)
    malos += q[i] != i * 2654435761u;
  printf ("dmabuf fd=%d tamaño=%lld, palabras distintas: %u de %u -> %s\n",
	  fd, (long long) t, malos, (unsigned) (TAM / 4), malos ? "MAL" : "OK");
  return malos != 0;
}
